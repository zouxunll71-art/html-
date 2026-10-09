"""Add new object fields without replacing existing project data or arrays."""
import copy

def fill_missing(state, defaults):
 changed = False
 if not isinstance(state, dict) or not isinstance(defaults, dict):return changed
 for key, value in defaults.items():
  if key not in state:
   state[key] = copy.deepcopy(value); changed = True
  elif isinstance(value, dict) and isinstance(state[key], dict):
   changed = fill_missing(state[key], value) or changed
 return changed
