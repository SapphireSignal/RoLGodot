"""A local stand-in for the closed Rise of Legions master server, for the reference build (docs/original-build.md).

The client talks to the master server by HTTP (Engine.Network.RPC: one URL per API method, GET query or POST form
fields in, JSON out, mapped onto the client's record / class types field by field; every field must be present).
This server reads the client's own API declarations from build/original/src (the [RpcUrl] attributes and the record,
class, enum and alias types they return), answers every endpoint with a complete default of its return type, and
overrides the answers a lobby screen needs with a sample account (SAMPLE below, cards from the snapshot).

    python tools/original_build/master_standin.py [--port 8765]

Every request is logged to build/original/standin.log (URL, parameters, answer size).
"""
import datetime
import email.parser
import email.policy
import glob
import json
import os
import re
import sys
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.environ.get('ORIGINAL_BUILD_DIR', os.path.join(ROOT, 'build', 'original'))
SRC = os.path.join(OUT, 'src')
LOG = os.path.join(OUT, 'standin.log')

INT_TYPES = {'integer', 'int64', 'cardinal', 'byte', 'word', 'uint64', 'uint32', 'int32', 'nativeint', 'shortint',
             'smallint', 'longint', 'longword', 'uint16', 'int16', 'uint8', 'int8'}
FLOAT_TYPES = {'single', 'double', 'extended', 'real', 'currency'}
STRING_TYPES = {'string', 'unicodestring', 'ansistring', 'widestring', 'shortstring', 'char', 'widechar'}
DATE_TYPES = {'tdatetime', 'tdate', 'ttime'}
MEMBER_KEYWORDS = ('function', 'procedure', 'constructor', 'destructor', 'property', 'class ', 'strict', 'private',
                   'protected', 'public', 'published', 'const', 'type', 'var', 'case', '[', '{', '//', 'end')


# ---------------------------------------------------------------------------------------------------------------
# The client's type declarations
# ---------------------------------------------------------------------------------------------------------------
class Types:
    def __init__(self, files):
        self.records = {}   # lower name -> (name, parent or None, [(field, type)])
        self.enums = {}     # lower name -> [values]
        self.aliases = {}   # lower name -> type text
        for f in files:
            self._read(f)

    def _read(self, path):
        lines = open(path, encoding='utf-8-sig', errors='replace').read().splitlines()
        i = 0
        while i < len(lines):
            line = lines[i]
            m = re.match(r'^(\s*)(\w+)\s*=\s*(packed\s+)?(record|class)\b\s*(\(([^)]*)\))?\s*(.*)$', line)
            if m and not re.match(r'^\s*(of\b|;)', m.group(7)) and 'abstract;' not in m.group(7):
                indent, name, kind, parent = m.group(1), m.group(2), m.group(4), m.group(6)
                fields, i = self._fields(lines, i + 1, indent)
                if parent:
                    parent = parent.split(',')[0].strip()
                key = name.lower()
                if key not in self.records or (kind == 'record' and not self.records[key][2]):
                    self.records[key] = (name, parent, fields)
                continue
            m = re.match(r'^\s*(\w+)\s*=\s*\(([^)]*)\)\s*;', line)
            if m:
                self.enums.setdefault(m.group(1).lower(), [v.strip().split('=')[0].strip()
                                                         for v in m.group(2).split(',')])
                i += 1
                continue
            m = re.match(r'^\s*(\w+)\s*=\s*(\w[\w.]*(?:\s*<[^;]+>)?|(?:array|set)\s+of\s+[\w.<>]+)\s*;\s*(//.*)?$', line)
            if m and m.group(2).lower() not in ('class', 'record', 'interface'):
                self.aliases.setdefault(m.group(1).lower(), m.group(2))
            i += 1

    @staticmethod
    def _fields(lines, i, indent):
        fields = []
        in_const = False
        while i < len(lines):
            raw = lines[i]
            s = raw.strip()
            if re.match(r'^end\s*;', s) and len(raw) - len(raw.lstrip()) <= len(indent) + 2:
                return fields, i + 1
            low = s.lower()
            if low in ('const', 'public const', 'private const', 'strict private const') or low.endswith(' const'):
                in_const = True
            elif re.match(r'^(public|private|protected|published|strict)\b', low):
                in_const = low.endswith('const')
            elif low.startswith(('function', 'procedure', 'constructor', 'destructor', 'property', 'class ')):
                # members end the field block of this section; a following visibility keyword may start fields again
                pass
            elif not in_const and not low.startswith(MEMBER_KEYWORDS):
                m = re.match(r'^([\w\s,]+?)\s*:\s*([^;=]+?)\s*;', s)
                if m:
                    for n in m.group(1).split(','):
                        fields.append((n.strip(), m.group(2).strip()))
            i += 1
        return fields, i

    def all_fields(self, key):
        name, parent, fields = self.records[key]
        result = []
        if parent and parent.lower() in self.records:
            result += self.all_fields(parent.lower())
        return result + fields

    def default(self, type_text, depth=0):
        t = type_text.strip()
        low = t.lower()
        if depth > 12:
            return None
        if low in INT_TYPES:
            return 0
        if low in FLOAT_TYPES:
            return 0.0
        if low == 'boolean':
            return False
        if low in STRING_TYPES:
            return ''
        if low in DATE_TYPES:
            return '2020-12-01T12:00:00'
        if low.startswith(('tarray<', 'array of', 'set of', 'tlist<', 'tobjectlist<')):
            return []
        if low in ('tjsondata', 'tjsonobject'):
            return {}
        if low in self.enums:
            return 0
        if low in self.aliases:
            return self.default(self.aliases[low], depth + 1)
        if low in self.records:
            return {n: self.default(ft, depth + 1) for n, ft in self.all_fields(low)}
        return None


def load_types():
    files = sorted(set(glob.glob(os.path.join(SRC, '*.pas')) + glob.glob(os.path.join(SRC, 'Engine', '*.pas'))))
    return Types(files)


def load_endpoints():
    """URL -> (method name, 'GET' / 'POST', return type) from the [RpcUrl] attributes."""
    result = {}
    for f in sorted(glob.glob(os.path.join(SRC, '*.pas'))):
        if not os.path.basename(f).lower().startswith('baseconflict.api'):
            continue
        lines = open(f, encoding='utf-8-sig', errors='replace').read().splitlines()
        for i, l in enumerate(lines):
            m = re.search(r"\[RpcUrl\('([^']+)'(?:,\s*(\w+))?", l)
            if not m:
                continue
            j = i + 1
            while lines[j].strip().startswith(('[', '///', '//')):
                j += 1
            sig = lines[j].strip()
            name = re.search(r'(?:function|procedure)\s+(\w+)', sig)
            ret = re.search(r'TPromise<(.+)>\s*;', sig)
            result[m.group(1)] = (name.group(1) if name else '?', 'GET' if m.group(2) == 'hmGET' else 'POST',
                                  ret.group(1).strip() if ret else 'Boolean')
    return result


# ---------------------------------------------------------------------------------------------------------------
# The sample account. Its values are made up (the real ones lived on the master server, docs/questions-for-devs.md);
# the cards come from the snapshot (src/content/cards.json, converted from BaseConflict.Constants.Cards.pas).
# ---------------------------------------------------------------------------------------------------------------
NOW = datetime.datetime(2020, 12, 1, 12, 0, 0)
SAMPLE = {
    'own_id': 1,
    'own_name': 'Reference',
    'level': 12,
    'balances': {'currency_gold': 12450, 'currency_diamonds': 380, 'currency_free_exp': 2600},
}
CURRENCIES = ['currency_gold', 'currency_diamonds', 'currency_free_exp']
MAX_LEAGUE, LEVEL_PER_LEAGUE, DECK_SLOTS = 5, 5, 12   # BaseConflict.Constants.Cards.pas, TDeck DECKSLOT_COUNT
COLOR_WHITE, COLOR_GREEN = 5, 2                        # EnumEntityColor ordinals


def load_cards():
    """(cards, skins by base uid) from the snapshot's card list: cards are ["card", UID, CardType, [Colors], Filename,
    Techlevel, SkinID], skins ["skin", BaseUID, UID, SkinID]; skin variants of a card are not cards of their own."""
    entries = json.load(open(os.path.join(ROOT, 'src', 'content', 'cards.json'), encoding='utf-8'))
    skins = {}
    skin_uids = set()
    for e in entries:
        if e[0] == 'skin':
            skins.setdefault(e[1], []).append({'id': len(skin_uids) + 1, 'uid': e[2], 'name': e[3]})
            skin_uids.add(e[2])
    cards = [e for e in entries if e[0] == 'card' and e[1] not in skin_uids]
    return cards, skins


def overrides(types):
    """URL -> function(params) returning the answer (a JSON-able value, or None for an empty 200)."""
    def rec(type_name, **values):
        d = types.default(type_name)
        for k, v in values.items():
            if k not in d:
                raise KeyError('%s has no field %s' % (type_name, k))
            d[k] = v
        return d

    def table(values):
        return [{'key': k, 'value': v} for k, v in values]

    cards, skins = load_cards()
    card_list = [rec('RCard', uid=c[1], name=c[4].split('\\')[-1], colors=c[3], starting_tier=1,
                     skins=skins.get(c[1], [])) for c in cards]
    # one instance of every card, leagues spread over 1..3 like a mid-level account
    instances = [rec('RCardInstance', id=i + 1, origin_card_uid=c[1], tier=1 + i % 3, experience_points=(i * 37) % 100,
                     ascension_progress=0, created=NOW.isoformat()) for i, c in enumerate(cards)]

    # player / deck icons: every picture in Graphics/GUI/Shared/Icons (HClient.GetPlayerIcon) is unlocked
    icon_dir = os.path.join(OUT, 'run', 'Graphics', 'GUI', 'Shared', 'Icons')
    icons = sorted(os.path.splitext(f)[0] for f in os.listdir(icon_dir)
                   if f.lower().endswith('.png') and not f.startswith('Unknown'))

    def deck(deck_id, name, color, icon):
        ids = [inst['id'] for inst, c in zip(instances, cards) if c[3] == [color]][:DECK_SLOTS]
        ids += [-1] * (DECK_SLOTS - len(ids))
        return rec('RDeck', id=deck_id, name=name, icon_identifier=icon,
                   Cards=[{'card_id': i, 'skin_id': -1} for i in ids])

    decks = [deck(1, 'White Legion', COLOR_WHITE, 'artwork_defender'),
             deck(2, 'Green Legion', COLOR_GREEN, 'artwork_forestguardian')]

    # the scenarios of the PLAY screen (TGameStateComponentMatchMaking.SCENARIO_MAPPING, Gamestates.pas:386) with their
    # player slots (team per slot) and one instance per league
    scenario_defs = [  # identifier, team slots, leagues, ranked
        ('pve_attack_solo', [1], 5, False), ('pve_attack', [1, 1], 5, False), ('1vs1', [1, 2], 5, False),
        ('2vs2', [1, 1, 2, 2], 5, False), ('two_lane_3vs3', [1, 1, 1, 2, 2, 2], 5, False),
        ('two_lane_4vs4', [1, 1, 1, 1, 2, 2, 2, 2], 5, False), ('ranked1vs1', [1, 2], 5, True),
        ('ranked2vs2', [1, 1, 2, 2], 5, True), ('duel', [1, 2], 5, False), ('duel2v2', [1, 1, 2, 2], 5, False),
        ('two_lane_duel3v3', [1, 1, 1, 2, 2, 2], 5, False), ('two_lane_duel4v4', [1, 1, 1, 1, 2, 2, 2, 2], 5, False),
        ('tutorial', [1], 1, False)]
    scenarios, instance_id = [], 0
    for ident, slots, leagues, ranked in scenario_defs:
        levels = []
        for tier in range(1, leagues + 1):
            instance_id += 1
            levels.append({'id': instance_id, 'tier': tier, 'mutators': []})
        scenarios.append(rec('RScenario', identifier=ident, enabled=True, slots=[{'team_id': s} for s in slots],
                             levels_of_difficulty=levels, ranked=ranked, minimum_playerlevel=1,
                             deck_required=ident != 'tutorial', staff_only=False))
    team = rec('RMatchmakingTeam', leader_id=SAMPLE['own_id'], team_uuid='reference-team',
               scenario_identifier='pve_attack_solo', scenario_instance_id=1, scenario_team=1,
               members=[{'id': SAMPLE['own_id'], 'username': SAMPLE['own_name'], 'current_deck': decks[0]['name'],
                         'deck_icon': decks[0]['icon_identifier'], 'deck_tier': 1}])

    return {
        '/api/shop/get_currencies/': lambda p: [rec('RCurrency', uid=u, name=u) for u in CURRENCIES],
        '/api/shop/get_balance/': lambda p: rec('RBalanceData', player_currency='currency_gold', balances=[
            {'currency_UID': u, 'balance': b} for u, b in SAMPLE['balances'].items()]),
        '/api/deckbuilding/get_card_constants/': lambda p: rec(
            'RCardConstants', gold_currency_uid='currency_gold', premium_currency_uid='currency_diamonds',
            card_gold_legendary_multiplier=2.0, card_max_tier=MAX_LEAGUE, card_level_per_tier=LEVEL_PER_LEAGUE,
            card_gold_value_table=table((l, 10 * l) for l in range(1, MAX_LEAGUE + 1)),
            card_upgrade_gold_cost=table((l, 100 * l) for l in range(1, MAX_LEAGUE + 1)),
            card_level_table=table((l, 100) for l in range(1, MAX_LEAGUE + 1)),
            card_experience_value_table=table((l, 10 * l) for l in range(1, MAX_LEAGUE + 1))),
        '/api/deckbuilding/get_cards/': lambda p: card_list,
        '/api/deckbuilding/get_card_unlocks/': lambda p: rec(
            'RUnlockData', card_unlocks=[{'card_uid': c[1]} for c in cards],
            skin_unlocks=[{'skin_id': s['id'], 'card_uid': base} for base, ss in skins.items() for s in ss]),
        '/api/deckbuilding/get_player_cards/': lambda p: instances,
        '/api/deckbuilding/get_decks/': lambda p: decks,
        '/api/game_manager/get_scenarios/': lambda p: scenarios,
        '/api/matchmaking/get_current_team/': lambda p: team,
        '/api/account/get_profile/': lambda p: rec(
            'RProfileData', experience_points=400, level=SAMPLE['level'], league=3, starterdeck_chosen=True,
            account_created='2019-03-01T12:00:00', next_first_win_available=NOW.isoformat(),
            premium_active_until='2020-01-01T12:00:00', deck_slots=5, icon='artwork_avenger'),
        '/api/account/get_unlocked_icons/': lambda p: icons,
        '/api/account/get_profile_constants/': lambda p: rec(
            'RProfileConstants', player_max_level=30,
            player_level_table=table((l, 1000 * l) for l in range(1, 31))),
        '/api/account/get_server_state/': lambda p: rec(
            'RServerState', max_current_player_online=1000, server_time=NOW.isoformat()),
        '/api/account/get_server_is_online/': lambda p: True,
        '/api/account/get_current_player_online/': lambda p: 1,
        '/api/account/get_max_current_player_online/': lambda p: 1000,
        '/api/account/login_steam/': lambda p: rec(
            'RLoginReturn', own_id=SAMPLE['own_id'], own_name=SAMPLE['own_name'], session_key='reference',
            broker_address='ws://127.0.0.1:1/', servertime=NOW.isoformat()),
        '/api/account/check_version/': lambda p: True,
    }


# ---------------------------------------------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------------------------------------------
class Handler(BaseHTTPRequestHandler):
    server_version = 'RoLStandin/1'

    def log_message(self, fmt, *args):
        pass

    def _params(self):
        url = urllib.parse.urlsplit(self.path)
        params = {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
        if self.command == 'POST':
            length = int(self.headers.get('Content-Length') or 0)
            body = self.rfile.read(length)
            ctype = self.headers.get('Content-Type', '')
            if 'multipart/form-data' in ctype:
                msg = email.parser.BytesParser(policy=email.policy.HTTP).parsebytes(
                    b'Content-Type: ' + ctype.encode() + b'\r\n\r\n' + body)
                for part in msg.iter_parts():
                    name = part.get_param('name', header='content-disposition')
                    params[name] = part.get_payload(decode=True).decode('utf-8', 'replace')
            elif body:
                params.update({k: v[0] for k, v in urllib.parse.parse_qs(body.decode('utf-8', 'replace')).items()})
        return url.path, params

    def _answer(self):
        path, params = self._params()
        st = self.server.state
        endpoint = st['endpoints'].get(path)
        status, body = 200, b''
        try:
            if path in st['overrides']:
                value = st['overrides'][path](params)
            elif endpoint:
                value = st['types'].default(endpoint[2])
                if endpoint[2].lower() == 'boolean':
                    value = None
            else:
                value, status = None, 404
            if value is not None:
                body = json.dumps(value).encode('utf-8')
        except Exception as e:
            status, body = 500, str(e).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        with st['lock']:
            with open(LOG, 'a', encoding='utf-8') as log:
                log.write('%s %s %s %s -> %d, %d bytes%s\n' % (
                    datetime.datetime.now().strftime('%H:%M:%S'), self.command, path,
                    json.dumps(params)[:300], status, len(body),
                    '' if endpoint or status != 404 else ' (unknown endpoint)'))

    do_GET = _answer
    do_POST = _answer


def main():
    port = int(sys.argv[sys.argv.index('--port') + 1]) if '--port' in sys.argv else 8765
    types = load_types()
    endpoints = load_endpoints()
    missing = [u for u, (_, _, r) in endpoints.items() if r.lower() != 'boolean' and types.default(r) is None]
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.state = {'types': types, 'endpoints': endpoints, 'overrides': overrides(types), 'lock': threading.Lock()}
    open(LOG, 'w').close()
    print('master stand-in on http://127.0.0.1:%d: %d endpoints, %d record/class types, %d enums; no default for %s'
          % (port, len(endpoints), len(types.records), len(types.enums), missing or 'none'), flush=True)
    server.serve_forever()


if __name__ == '__main__':
    main()
