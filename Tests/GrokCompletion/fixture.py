import json,os,signal,sys,time
mode,pidfile=sys.argv[1:]
with open(pidfile,'w') as f:f.write(str(os.getpid()))
record=dict(type='result',subtype='success',is_error=False,stop_reason='end_turn',result='완성 결과')
def emit(o):print(json.dumps(o,ensure_ascii=False),flush=True)
if mode in ('hang','success-hang'):
 signal.signal(signal.SIGTERM,signal.SIG_IGN)
 if mode=='success-hang':emit(record)
 time.sleep(10)
elif mode=='success':
 os.write(2,b'x'*200000)
 emit(dict(type='stream_event',event=dict(type='content_block_delta',delta=dict(type='text_delta',text='미완성'))))
 data=(json.dumps(record,ensure_ascii=False)+'\n').encode()
 os.write(1,data[:12]);time.sleep(.08);os.write(1,data[12:]);time.sleep(2)
elif mode=='partial':emit(dict(type='assistant',message=dict(content=[dict(type='text',text='부분결과')])))
elif mode=='error':emit(dict(record,subtype='error',is_error=True));sys.exit(1)
elif mode=='empty':emit(dict(record,result=' '))
elif mode=='limit':emit(dict(record,stop_reason='max_tokens'))
elif mode=='oversized':os.write(1,b'x'*1100000+b'\n');emit(record)
elif mode=='truncated':os.write(1,b'{"type":"result",')
elif mode=='malformed':print('not json',flush=True)
