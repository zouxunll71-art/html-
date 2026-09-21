"""Read OpenType PostScript names from owned font assets."""
import struct
def postscript_name(path):
 data=path.read_bytes()
 try:
  count=struct.unpack_from('>H',data,4)[0]
  for i in range(count):
   tag,_,offset,_=struct.unpack_from('>4sIII',data,12+i*16)
   if tag!=b'name':continue
   _,entries,strings=struct.unpack_from('>HHH',data,offset)
   for j in range(entries):
    platform,encoding,language,name,size,start=struct.unpack_from('>HHHHHH',data,offset+6+j*12)
    if name==6:
     raw=data[offset+strings+start:offset+strings+start+size]
     return raw.decode('utf-16-be' if platform in (0,3) else 'mac_roman')
 except (struct.error,UnicodeError):pass
 return ''
