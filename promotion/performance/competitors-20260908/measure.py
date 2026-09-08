import ctypes,json,time,subprocess,sys,pathlib
class R(ctypes.Structure):
 _fields_=[('uuid',ctypes.c_byte*16)]+[(k,ctypes.c_uint64) for k in ['user','system','pkg','interrupt','pageins','wired','resident','footprint','start','exit']]
lib=ctypes.CDLL('/usr/lib/libproc.dylib')
lib.proc_pid_rusage.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_void_p]
def sample(pid):
 r=R()
 if lib.proc_pid_rusage(pid,0,ctypes.byref(r)): raise RuntimeError('rusage failed')
 return {'footprint_MiB':r.footprint/1048576,'rss_MiB':r.resident/1048576,'cpu_seconds':(r.user+r.system)/1e9}
class Timebase(ctypes.Structure):
 _fields_=[('numer',ctypes.c_uint32),('denom',ctypes.c_uint32)]
tb=Timebase();ctypes.CDLL('/usr/lib/libSystem.B.dylib').mach_timebase_info(ctypes.byref(tb))
# proc rusage task times use mach absolute ticks on this host; checked against ps TIME.
factor=tb.numer/tb.denom
_original_sample=sample
def sample(pid):
 d=_original_sample(pid);d['cpu_seconds']*=factor;return d
pid=int(sys.argv[1]);stage=sys.argv[2];t=time.monotonic();a=sample(pid);time.sleep(30);b=sample(pid);duration=time.monotonic()-t
row={'cpu_timebase_factor':factor,'pid':pid,'stage':stage,'wall_seconds':duration,'start':a,'end':b,'cpu_percent_one_core':100*(b['cpu_seconds']-a['cpu_seconds'])/duration}
p=pathlib.Path(__file__).parent/'samples.jsonl'
with p.open('a') as f:f.write(json.dumps(row)+'\n')
print(json.dumps(row))
