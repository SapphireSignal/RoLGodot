"""Prepare the reference build of the original (docs/original-build.md).

Copies the code of reference/rise-of-legions into build/original/src, applies the changes Delphi 13 Community needs
(each one checked: a missing anchor stops the script), writes the patched FMX.Canvas.D2D from the installed Delphi's
own source, and lays out build/original/run (links to the snapshot's data, copies of what the game writes to).
The snapshot itself is never modified. Building happens in the Delphi IDE (delphi_build.ps1).

    python tools/original_build/prepare_original.py [--run-only]
"""
import os
import shutil
import subprocess
import sys
import zipfile
import io

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF = os.path.join(ROOT, 'reference', 'rise-of-legions')
OUT = os.environ.get('ORIGINAL_BUILD_DIR', os.path.join(ROOT, 'build', 'original'))
SRC = os.path.join(OUT, 'src')
RUN = os.path.join(OUT, 'run')
HERE = os.path.dirname(os.path.abspath(__file__))
DELPHI_FMX = r'C:\Program Files (x86)\Embarcadero\Studio\37.0\source\fmx\FMX.Canvas.D2D.pas'

CODE_EXT = ('.pas', '.dpr', '.dproj', '.dfm', '.inc', '.res', '.rc', '.vrc', '.ico', '.manifest', '.groupproj', '.obj')
TEXT_EXT = ('.pas', '.dpr', '.inc')


def read_text(path):
    """Delphi source as str: UTF-8 (with or without BOM) or the original's Windows-1252."""
    b = open(path, 'rb').read()
    if b.startswith(b'\xef\xbb\xbf'):
        return b[3:].decode('utf-8')
    try:
        return b.decode('utf-8')
    except UnicodeDecodeError:
        return b.decode('cp1252')


def write_text(path, text):
    """UTF-8 with BOM when non-ASCII: Delphi 13 reads BOM-less files as UTF-8, the original saved Windows-1252."""
    data = text.encode('utf-8')
    if any(ord(c) > 127 for c in text):
        data = b'\xef\xbb\xbf' + data
    open(path, 'wb').write(data)


def patch(rel, old, new, count=1):
    path = os.path.join(SRC, rel)
    text = read_text(path)
    found = text.count(old)
    if found == 0 and '\r\n' not in text:   # some of the original's files use LF line ends
        old, new = old.replace('\r\n', '\n'), new.replace('\r\n', '\n')
        found = text.count(old)
    if found != count:
        sys.exit('patch anchor found %d times (expected %d) in %s:\n%s' % (found, count, rel, old))
    write_text(path, text.replace(old, new))


def copy_code():
    # overwrites in place (a running IDE holds the folders open, so no delete); keeps the .dcu files for fast builds
    for base, dirs, files in os.walk(REF):
        dirs[:] = [d for d in dirs if d not in ('.git', 'Deploy')]
        for f in files:
            if not f.lower().endswith(CODE_EXT):
                continue
            src = os.path.join(base, f)
            dst = os.path.join(SRC, os.path.relpath(src, REF))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
    # resource script inputs: the engine shaders (Engine\Shader\Shader.rc) and the splash (Splash.rc)
    shutil.copytree(os.path.join(REF, 'Engine', 'Shader'), os.path.join(SRC, 'Engine', 'Shader'), dirs_exist_ok=True)
    shutil.copy2(os.path.join(REF, 'Splash.png'), SRC)
    # every Windows-1252 source file to UTF-8 with BOM (identifiers like TasteRücktaste, string literals)
    for base, dirs, files in os.walk(SRC):
        for f in files:
            if f.lower().endswith(TEXT_EXT):
                p = os.path.join(base, f)
                write_text(p, read_text(p))


def apply_patches():
    # madExcept (commercial, not installed): a stub with the calls the code makes
    shutil.copy2(os.path.join(HERE, 'madExcept.pas'), os.path.join(SRC, 'Engine', 'madExcept.pas'))
    dpr =os.path.join('GameServer', 'RiseOfLegionsGameServer.dpr')
    for unit in ('madExcept', 'madLinkDisAsm', 'madListHardware', 'madListProcesses', 'madListModules'):
        patch(dpr, '  %s,\r\n' % unit, '')
    # the server project defaults to Win64, whose compiler crashes the IDE here; the client is Win32 only anyway
    patch(os.path.join('GameServer', 'RiseOfLegionsGameServer.dproj'),
          "<Platform Condition=\"'$(Platform)'==''\">Win64</Platform>",
          "<Platform Condition=\"'$(Platform)'==''\">Win32</Platform>")
    # LockBox: TMemoryStream.Realloc takes a NativeInt since Delphi XE2+
    lb = os.path.join('Engine', 'lockbox', 'uTPLb_MemoryStreamPool.pas')
    patch(lb, 'function Realloc( var NewCapacity: Longint): Pointer; override;',
          'function Realloc( var NewCapacity: NativeInt): Pointer; override;')
    patch(lb, 'function TPooledMemoryStream.Realloc( var NewCapacity: Integer): Pointer;',
          'function TPooledMemoryStream.Realloc( var NewCapacity: NativeInt): Pointer;')
    # DWScript picks the TTypeKind name table by exact compiler version (VER330); Delphi 13 has the 23-kind enum
    rtti = os.path.join('Engine', 'DWScript', 'dwsRTTIExposer.pas')
    text = read_text(os.path.join(SRC, rtti))
    start = text.index('  {$IFDEF VER330}')
    end = text.index('  {$ENDIF}', start) + len('  {$ENDIF}')
    block = text[start:end]
    if 'cTYPEKIND_NAMES' not in block:
        sys.exit('dwsRTTIExposer: VER330 block not found')
    keep = block[block.index('  cTYPEKIND_NAMES'):block.index('  {$ELSE}')]
    write_text(os.path.join(SRC, rtti), text[:start] + keep.rstrip('\r\n') + text[end:])
    # Engine.Collision: the nested generic array type crashes Delphi 13's compiler (the whole IDE, APPCRASH)
    col = os.path.join('Engine', 'Engine.Collision.pas')
    patch(col, 'AChildren<Tnx> = array [0 .. CHILDCOUNT - 1] of TLooseQuadTreeNode<Tnx>;',
          'AChildren = array [0 .. CHILDCOUNT - 1] of TLooseQuadTreeNode<T>;')
    patch(col, 'FChildren : AChildren<T>;', 'FChildren : AChildren;')
    # the engine's fixed copy of Winapi.D3D11 clashes with Delphi 13's precompiled FMX.Context.DX11 (F2051);
    # Delphi 13's own header has the fixes
    patch('RiseOfLegions.dpr', "  Winapi.D3D11 in 'Engine\\FixedDX11Header\\Winapi.D3D11.pas',\r\n", '')
    patch('RiseOfLegions.dproj', '        <DCCReference Include="Engine\\FixedDX11Header\\Winapi.D3D11.pas"/>\r\n', '')
    os.replace(os.path.join(SRC, 'Engine', 'FixedDX11Header', 'Winapi.D3D11.pas'),
              os.path.join(SRC, 'Engine', 'FixedDX11Header', 'Winapi.D3D11.pas.engine-fixed'))
    # a detailed map file, to resolve logged crash addresses (resolve_map.py)
    patch('RiseOfLegions.dproj', "    <PropertyGroup Condition=\"'$(Base)'!=''\">\r\n",
          "    <PropertyGroup Condition=\"'$(Base)'!=''\">\r\n        <DCC_MapFile>3</DCC_MapFile>\r\n")
    # fonts: the original patched Embarcadero's FMX.Canvas.D2D (Engine\FixedDX11Header\FMX.Canvas.D2D.diff) with
    # LoadFontFromFile; Delphi 13's FMX loads custom fonts itself (TFontManager), and a changed interface of that unit
    # would break every precompiled FMX unit using it
    gfx = os.path.join('Engine', 'Engine.GfxApi.pas')
    patch(gfx, '  FMX.Canvas.D2D,\r\n', '  FMX.Canvas.D2D,\r\n  FMX.FontManager,\r\n')
    patch(gfx, 'FMX.Canvas.D2D.TCustomCanvasD2D.LoadFontFromFile(Path);',
          'FMX.FontManager.TFontManager.AddCustomFontFromFile(Path);')
    fmx = read_text(DELPHI_FMX)
    for old, new in (
            ('      FTarget.SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_DEFAULT);',
             '      FTarget.SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE); // FMX.Canvas.D2D.diff'),
            ('    InitThemeLibrary and UseThemes and TCustomCanvasD2D.TryCreateDirect3DDevice then',
             '    { InitThemeLibrary and UseThemes and } TCustomCanvasD2D.TryCreateDirect3DDevice then // FMX.Canvas.D2D.diff')):
        if fmx.count(old) != 1:
            sys.exit('FMX.Canvas.D2D anchor not found: ' + old)
        fmx = fmx.replace(old, new)
    write_text(os.path.join(SRC, 'Engine', 'FixedDX11Header', 'FMX.Canvas.D2D.pas'), fmx)
    # Delphi 10.1's x87 code made NaN <= x true, so RVector3.EMPTY (X = NaN) passed this check; Delphi 13 is IEEE.
    # "Some component greater" answers the same under both rules. Reports the caller when it does fail.
    patch(os.path.join('Engine', 'Engine.Math.Collision3D.pas'),
          "  assert(Min <= Max, 'RAABB.CreateAABB: Min must be smaller than Max in each direction!')\r\n",
          "  if (Min.X > Max.X) or (Min.Y > Max.Y) or (Min.Z > Max.Z) then\r\n"
          "      raise EAssertionFailed.CreateFmt('RAABB.Create Min %.3f %.3f %.3f Max %.3f %.3f %.3f caller %p',\r\n"
          "      [Min.X, Min.Y, Min.Z, Max.X, Max.Y, Max.Z, ReturnAddress]);\r\n")
    # the client swallows every exception silently (ApplicationEvents1Exception): log each distinct one
    patch('BaseConflictMainUnit.pas',
          'procedure THauptform.ApplicationEvents1Exception(Sender : TObject; E : Exception);\r\nbegin\r\n',
          'procedure THauptform.ApplicationEvents1Exception(Sender : TObject; E : Exception);\r\n'
          '{$WRITEABLECONST ON}\r\nconst\r\n  LastLogged : string = \'\';\r\n  {$WRITEABLECONST OFF}\r\nbegin\r\n'
          '  if E.ClassName + \': \' + E.Message <> LastLogged then\r\n  begin\r\n'
          '    LastLogged := E.ClassName + \': \' + E.Message;\r\n'
          '    HLog.Log(\'[EXCEPTION] \' + LastLogged + \' at \' + IntToHex(NativeUInt(ExceptAddr), 8));\r\n  end;\r\n')
    # a failing TClientGame.Create ran the destructor, whose ClearAction on the missing component hid the real error
    patch('BaseConflict.Game.Client.pas', '  FClientInputComponent.ClearAction;\r\n',
          '  if assigned(FClientInputComponent) then FClientInputComponent.ClearAction;\r\n')
    # diagnostics: the client drops the GUI's style errors (no Erroroutput), dXML expression errors (elDebug) and
    # console messages (a DEBUG build's console window, which pops up over the game and takes clicks and captures);
    # HLog.LogOnce writes each distinct one to Error.log instead
    log = os.path.join('Engine', 'Engine.Log.pas')
    patch(log, '      class procedure Log(LogMessage : string); overload; static;\r\n',
          '      class procedure Log(LogMessage : string); overload; static;\r\n'
          '      class procedure LogOnce(const LogMessage : string); static;\r\n')
    patch(log, 'uses\r\n  Engine.Helferlein.Windows;\r\n\r\n',
          'uses\r\n  Engine.Helferlein.Windows;\r\n\r\nvar\r\n  LoggedOnce : TStringList;\r\n\r\n'
          'class procedure HLog.LogOnce(const LogMessage : string);\r\nvar\r\n  Index : integer;\r\nbegin\r\n'
          '  Semaphore.Acquire;\r\n  if not assigned(LoggedOnce) then\r\n  begin\r\n'
          '    LoggedOnce := TStringList.Create;\r\n    LoggedOnce.Sorted := True;\r\n  end;\r\n'
          '  if LoggedOnce.Find(LogMessage, Index) or (LoggedOnce.Count >= 5000) then\r\n  begin\r\n    Semaphore.Release;\r\n    exit;\r\n  end;\r\n'
          '  LoggedOnce.Add(LogMessage);\r\n  Semaphore.Release;\r\n  HLog.Log(LogMessage);\r\nend;\r\n\r\n')
    patch(log, 'class procedure HLog.Console(LogMessage : string; NewLine : boolean);\r\nbegin\r\n',
          'class procedure HLog.Console(LogMessage : string; NewLine : boolean);\r\nbegin\r\n'
          '  HLog.LogOnce(\'[CONSOLE] \' + LogMessage);\r\n  Exit; // no console window: it pops up over the game\r\n')
    patch(os.path.join('Engine', 'Engine.dXML.pas'),
          "      HLog.Write(elDebug, 'TdXMLNode.TDynamicTextField.TDynamicPart.GetString: Cannot evaluate expression",
          "      HLog.LogOnce('[dXML] ' + Format('TdXMLNode.TDynamicTextField.TDynamicPart.GetString: Cannot evaluate expression")
    patch(os.path.join('Engine', 'Engine.dXML.pas'),
          'Error: %s\', [FRawExpression, e.Message]);\r\n', 'Error: %s\', [FRawExpression, e.Message]));\r\n')
    patch('BaseConflictMainUnit.pas', '  Engine.GUI.GUI := GUI;\r\n',
          '  Engine.GUI.GUI := GUI;\r\n  GUI.Erroroutput := procedure(errormsg : string)\r\n    begin\r\n'
          '      HLog.LogOnce(\'[GUI] \' + errormsg);\r\n    end;\r\n')
    # the lobby (master_standin.py): the login always asks Steam for a ticket, also in the Steamless configuration
    # this build uses; without STEAM a placeholder ticket and build id go to the stand-in, the rest is the original's
    acc = 'BaseConflict.Api.Account.pas'
    patch(acc, '      if not TryGetSteamTicket(EncodedSteamTicket) then\r\n          continue;\r\n',
          '      {$IFDEF STEAM}\r\n      if not TryGetSteamTicket(EncodedSteamTicket) then\r\n          continue;\r\n'
          '      {$ELSE}\r\n      EncodedSteamTicket := \'reference\';\r\n      {$ENDIF}\r\n')
    patch(acc, '      GetLocalVersion(SteamAppBuildId, BranchName);\r\n',
          '      {$IFDEF STEAM}\r\n      GetLocalVersion(SteamAppBuildId, BranchName);\r\n'
          '      {$ELSE}\r\n      SteamAppBuildId := 0;\r\n      BranchName := \'public\';\r\n      {$ENDIF}\r\n')
    # the loader ignores a stylesheet's parse errors on first load (only reloads report them): log them
    patch(os.path.join('Engine', 'Engine.GUI.pas'), '    LoadStylesFromText(Filecontent);\r\n',
          '    errors := LoadStylesFromText(Filecontent);\r\n'
          '    if errors <> \'\' then HLog.LogOnce(\'[STYLE] \' + Filepath + \': \' + errors);\r\n')


def link(name):
    dst = os.path.join(RUN, name)
    if not os.path.exists(dst):
        subprocess.run(['cmd', '/c', 'mklink', '/J', dst, os.path.join(REF, name)], check=True, capture_output=True)


def mirror_crlf(names):
    """The snapshot's text files are stored with LF (git normalised them); the devs' checkouts (autocrlf) and the
    shipped game had CRLF, and the original's parsers split on CRLF (stylesheets, shaders, terrain). Mirrors `names`
    into run/ as a CRLF checkout would be: text files (git's own classification) written with CRLF, every other file
    hard-linked to the snapshot (same volume, no copy)."""
    out = subprocess.run(['git', '-C', REF, 'ls-files', '--eol', '--'] + list(names),
                         check=True, capture_output=True, text=True, encoding='utf-8').stdout
    for line in out.splitlines():
        meta, rel = line.split('\t', 1)
        src, dst = os.path.join(REF, rel), os.path.join(RUN, rel)
        if os.path.exists(dst) and os.path.getmtime(dst) >= os.path.getmtime(src):
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.exists(dst):
            os.remove(dst)
        if meta.startswith('i/lf'):
            data = open(src, 'rb').read().replace(b'\r\n', b'\n').replace(b'\n', b'\r\n')
            open(dst, 'wb').write(data)
        else:
            os.link(src, dst)


def lay_out_run():
    os.makedirs(os.path.join(RUN, 'GameServer'), exist_ok=True)
    # read-only data as the shipped game had it (CRLF text), links into the snapshot otherwise
    data = ('Graphics', 'Maps', 'Scripts', 'Lang')
    for name in data:
        dst = os.path.join(RUN, name)
        if os.path.isjunction(dst):   # earlier layouts linked the whole folder
            os.rmdir(dst)
    mirror_crlf(data)
    link('PrecompiledDX11ShadersCached')
    # the engine writes newly compiled shaders here: a copy
    if not os.path.isdir(os.path.join(RUN, 'PrecompiledDX11Shaders')):
        shutil.copytree(os.path.join(REF, 'PrecompiledDX11Shaders'), os.path.join(RUN, 'PrecompiledDX11Shaders'))
    # sound: a copy, with the music bank the repository ships as a split zip unpacked
    banks = os.path.join(RUN, 'Sound', 'Banks')
    if not os.path.isfile(os.path.join(banks, 'Music.bank')):
        shutil.copytree(os.path.join(REF, 'Sound'), os.path.join(RUN, 'Sound'), dirs_exist_ok=True)
        parts = sorted(f for f in os.listdir(banks) if f.startswith('Music.bank.zip.'))
        data = b''.join(open(os.path.join(banks, f), 'rb').read() for f in parts)
        zipfile.ZipFile(io.BytesIO(data)).extractall(banks)
        for f in parts:
            os.remove(os.path.join(banks, f))
    for f in os.listdir(REF):
        if f.lower().endswith(('.dll', '.ini')) or f in ('PostEffects.fxs', 'PreloaderCache.xml', 'Splash.png'):
            shutil.copy2(os.path.join(REF, f), RUN)


def main():
    if not os.path.isdir(REF):
        sys.exit('reference/ is missing: run tools/fetch_reference.ps1 first')
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(ROOT, 'build', '.gdignore'), 'a').close()
    if '--run-only' not in sys.argv:
        copy_code()
        apply_patches()
        print('prepared', SRC)
    lay_out_run()
    print('laid out', RUN)


if __name__ == '__main__':
    main()
