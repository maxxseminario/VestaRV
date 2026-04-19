try:
    import RPi.GPIO as GPIO
    HAS_GPIO = True
except ImportError:
    print("Warning: RPi.GPIO not available. DPS functionality will be stubbed.")
    HAS_GPIO = False
    
from time import sleep
import queue

# DPS test PCB data (with multiple tapers for the green pcbs)

# Purple
#a_value =  300  # 850V
#a_value =  400  # 800V
#a_value =  500  # 750V
#a_value =  800  # 615V
#a_value =  900  # 570V
#a_value = 1000  # 525

# Green 331113
#a_value = 1175  # 450 V
#a_value = 1070  # 500 V
#a_value =  967  # 550 V
#a_value =  853  # 600 V
#a_value =  747  # 650 V
#a_value =  640  # 700 V
#a_value =  524  # 750 V
#a_value =  408  # 800 V
#a_value =  296  # 850 V

class DPS:

    PIN_SCLK = 36
    PIN_MOSI = 38
    PIN_CS   = 40

    # Queue of setting updates
    q = None

    # Flag to prevent repeated calls from corrupting the transmission.
    interface_in_use = False 

    def __init__(self):
        self.q = queue.Queue(maxsize=1000)
        if HAS_GPIO:
            mode = GPIO.setmode(GPIO.BOARD)
            GPIO.setwarnings(False)
            GPIO.setup(self.PIN_CS,   GPIO.OUT, initial=GPIO.HIGH)
            GPIO.setup(self.PIN_MOSI, GPIO.OUT, initial=GPIO.HIGH)
            GPIO.setup(self.PIN_SCLK,  GPIO.OUT, initial=GPIO.HIGH)
        else:
            print("DPS: GPIO not available, running in stub mode")

    def write(self, a_value):

        self.q.put(a_value)

        # If interface is idle, lock it and begin transmission
        if self.interface_in_use:
            return False

        self.interface_in_use = True
        
        if not HAS_GPIO:
            # Stub mode - just print what would be written
            while not self.q.empty():
                x = self.q.get()
                print(f"DPS (stub): Would write value {x}")
            self.interface_in_use = False
            print('DPS Voltage Set (stub mode)')
            return True
        
        while not self.q.empty():
            x = self.q.get()
            codeword = ((x << 1) & 0b111111000000) + (x & 0b11111);
            codeword = codeword & 0b111111111111
            GPIO.output(self.PIN_CS, 1)
            GPIO.output(self.PIN_SCLK, 1)
            sleep(10e-3)
            GPIO.output(self.PIN_CS, 0)
            GPIO.output(self.PIN_SCLK, 0)
            sleep(10e-3)
            for i in range(12)[::-1]:
                if (codeword >> i) & 0x1:
                    GPIO.output(self.PIN_MOSI, 1)
                else:
                    GPIO.output(self.PIN_MOSI, 0)
                sleep(10e-3)
                GPIO.output(self.PIN_SCLK, 1)
                sleep(10e-3)
                GPIO.output(self.PIN_SCLK, 0)
            sleep(10e-3)
            GPIO.output(self.PIN_CS, 1)
            sleep(10e-3)
            GPIO.output(self.PIN_SCLK, 1)
            GPIO.output(self.PIN_MOSI, 1)
            sleep(10e-3)

        self.interface_in_use = False
        print('DPS Voltage Set')
        return True

