"""Export the current composed iOS appearance, never resurrect stale source layers."""
import copy

EDITOR_DEFAULTS={'fontName':'','asset':'','capPixels':0,'capPoints':13,'anchor':'topLeft'}

def meaningful_patch(patch,base):
 # Only absent source fields with the editor's exact defaults are serialization noise.
 return {key:value for key,value in patch.items() if not (key not in base and key in EDITOR_DEFAULTS and type(value) in (str,int,float) and value==EDITOR_DEFAULTS[key])}

def prepare(record):
 snapshot=copy.deepcopy(record)
 conflicts=snapshot.get('conflicts',[])
 report={'policy':'current-ios-appearance','conflicts':copy.deepcopy(conflicts),'notes':[
  'Existing iOS overrides remain authoritative exactly as in the composed preview.',
  'Overrides for absent source nodes stay inert; no deleted layer is recreated.',
  'All declared pages and dialogs are exported, not a screenshot of the current page.',
  'Source freshness, assets, localization, actions and outer-project protection still apply.'
 ]}
 # compose already applies overrides only to present source nodes. Preserve them
 # verbatim so conditional and repeated layers retain their current behavior.
 snapshot['conflicts']=[]
 return snapshot,report
