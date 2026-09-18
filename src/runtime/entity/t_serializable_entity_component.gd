class_name TSerializableEntityComponent
extends TEntityComponent
## Port of TSerializableEntityComponent (BaseConflict.Entity.pas:304, implementation :2117).
## Thin for now: the RTTI stream serialisation (Serialize on eiSerialize, Deserialize, GetBaseType) is phase 3,
## with client-server sync. Components that extend it behave like plain TEntityComponents until then.
