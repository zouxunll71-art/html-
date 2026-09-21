"""Exports run off the UI state lock, with progress for large asset catalogs."""
import copy,threading,time,uuid
JOBS={};LOCK=threading.RLock();ACTIVE=None

def status(job):
 with LOCK:
  if job not in JOBS:raise ValueError('导出任务不存在')
  return copy.deepcopy(JOBS[job])

def start(record,export):
 global ACTIVE
 with LOCK:
  if ACTIVE and JOBS[ACTIVE]['state']=='running':raise ValueError('已有工程正在导出，请等待完成')
  job=uuid.uuid4().hex;ACTIVE=job;JOBS[job]={'id':job,'state':'running','projectID':record['id'],'stage':'准备导出','progress':0,'started':time.time()}
 def update(stage,progress):
  with LOCK:JOBS[job].update(stage=stage,progress=progress)
 def work():
  try:
   path=export(record,update)
   with LOCK:JOBS[job].update(state='done',stage='导出完成',progress=100,path=path)
  except Exception as error:
   with LOCK:JOBS[job].update(state='failed',stage='导出未完成',error=str(error))
 threading.Thread(target=work,daemon=True).start();return job
