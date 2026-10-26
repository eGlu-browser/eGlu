import subprocess, time, sys
from PIL import Image
import os; D=os.environ.get('DEVICE', 'booted'); p=sys.argv[1]+'/poll.png'
for i in range(90):
    subprocess.run(['xcrun','simctl','io',D,'screenshot',p],capture_output=True)
    r,g,b=Image.open(p).convert('RGB').getpixel((420,2352))
    if r<60 and b>200:
        print('ready', i, time.time()); break
    time.sleep(2.5)
else: print('timeout')
