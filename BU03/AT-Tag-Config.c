
if uart.any():
    message = uart.read()
    print(message)
    
time.sleep(3)    

uart.write('AT+SAVE\r\n')

time.sleep(3)

if uart.any():
    message = uart.read()
    print(message)
    
    
uart.write('AT+GETCFG\r\n')

time.sleep(0.1)

if uart.any():
    message = uart.read()
    print(message)