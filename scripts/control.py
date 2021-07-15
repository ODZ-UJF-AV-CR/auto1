#!/usr/bin/env python3

# Scripts for control DS7000 oscilloscope, Chronos camera and Ublox GPS for Car No.1

import sys
import time

import ublox # pyUblox librarie
import util
import datetime

import vxi11 # oscilloscope control

import requests # http camera control

class TmcDriver:

    def __init__(self, device):
        print("#Initializing connection to: " + device)
        self.device = device
        self.instr = vxi11.Instrument(device)
 
    def write(self, command):
        #print command
        self.instr.write(command);

    def read(self, length = 500):
        return self.instr.read(length)

    def read_raw(self, length = 500):
        return self.instr.read_raw(length)
 
    def getName(self):
        self.write("*IDN?")
        return self.read(300)
    
    def ask(self, command):
        return self.instr.ask(command)
 
    def sendReset(self):
        self.write("*RST")  # Be carefull, this real resets an oscilloscope
        

#camera_url = "http://chronos.lan"
camera_url = "http://192.168.1.11"

#Camera control is inspired by https://github.com/krontech/chronos-examples/tree/master/python3

# setting camera
post = requests.post(camera_url+'/control/p', json = {'backlightEnabled': False })
if post.reason == "OK" :
	print("#Camera LCD backlight sucesfully Disabled")
else:
    print("#Error - " + post)
print('#Setting camera')
post = requests.post(camera_url+'/control/stopRecording')
print(post.reason)
post = requests.post(camera_url+'/control/flushRecording')
print(post.reason)
post = requests.post(camera_url+'/control/p', json = {'resolution': {'hRes': 928, 'vRes': 928, 'hOffset': 176, 'vOffset': 66}})
print(post.reason)
post = requests.post(camera_url+'/control/p', json = {'recMaxFrames':3226})  # cca 2 s
post = requests.post(camera_url+'/control/p', json = {'recTrigDelay':1613})  # This value is only informative (it works for HW trigger only)
print(post.reason)
print('#Please readjust shutter manually !!!!!!!!!!!!!!!!!!!!')


# For Ethernet for oscilloscope for VXI
osc = TmcDriver("TCPIP::192.168.1.10::INSTR")
print('#' + osc.ask("*IDN?"))

# Open GPS port
gpsport = '/dev/ttyACM0'
gpsbaudrate = 921600
dev = ublox.UBlox(gpsport, baudrate=gpsbaudrate, timeout=0)
msg = dev.receive_message() #dummy GPS read for connection check

while True:        
    print('#Start camera recording')
    post = requests.post(camera_url+'/control/startRecording', json = {'recMode': 'normal'})
    print(post.reason)
    
    print('#Waiting...')
    sys.stdout.flush()
    osc.write(":SINGLE")
    
    # Read GPS messages, if any
    while True:
        try:
            msg = dev.receive_message()
        except:
            continue
			
        if (msg is None):
            continue
        else:
            print('#', msg)
            if ((msg.name() == 'TIM_TM2')):
                break


    # Chronos camera
    time.sleep(1)
    post = requests.post(camera_url+'/control/stopRecording')

    # RIGOL DS7014
    #osc.write(":STOP")
    print('#stop')

    try:
        msg.unpack()
        timestring = '$HIT,'
        timestring += str(msg.count)
        timestring += ','
        timestring += str(datetime.datetime.utcnow())
        timestring += ','
        filename = util.gpsTimeToTime(msg.wnR, 1.0e-3*msg.towMsR + 1.0e-9*msg.towSubMsR)
        timestring += str(filename)
        timestring += ','
        timestring += str(datetime.datetime.utcfromtimestamp(filename))
        print(timestring)
        sys.stdout.flush()

    except ublox.UBloxError as e:
        print(e)

    # waiting for sawings
    print('#press sssss for saving waveform'),
    sys.stdout.flush()
    ble = input()
    print(ble)
    if (len(ble)>0):
        if (ble[0]=='s'):
            mp4filename = str(filename) + ".mp4"
            print('#OK')
        
            osc.write(':SAVE:WAVeform D:\\blesky\\' + str(filename) + '.wfm')
            print('#Saving waveform...')

            post = requests.post(camera_url+'/control/startFilesave', json = {'format': 'h264', 'device': 'mmcblk1p1', 'filename': mp4filename})
            if post.reason == "OK" :
            	print("#Saving video...")
            else:
                print("#Error - Unable to save the video")
                print(post)

            # waiting for sawings
            print('#press Enter to continue'),
            sys.stdout.flush()
            input()
        
    # flush GPS buffer
    while (True):
        try:
            msg = dev.receive_message()
        except:
            break
            
        if (msg is None):
            break




