
#include <TimerOne.h>
#include <TimerThree.h>

//light linearizer. see http://jared.geek.nz/2013/feb/linear-led-pwm
const uint16_t cie_10b[256] = {
        0, 0, 1, 1, 2, 2, 3, 3, 4, 4,
        4, 5, 5, 6, 6, 7, 7, 8, 8, 8,
        9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
        14, 15, 15, 16, 17, 17, 18, 19, 19, 20,
        21, 22, 22, 23, 24, 25, 26, 27, 28, 29,
        30, 31, 32, 33, 34, 35, 36, 37, 38, 39,
        40, 42, 43, 44, 45, 47, 48, 50, 51, 52,
        54, 55, 57, 58, 60, 61, 63, 65, 66, 68,
        70, 71, 73, 75, 77, 79, 81, 83, 84, 86,

        /*
        0,1,2,3,4,5,6,7,8,9,    //linear on the low end
        10,11,12,13,14,15,16,17,18,19,
        20,21,22,23,24,25,26,27,28,29,
        30,31,32,33,34,35,36,37,38,39,
        40,41,42,43,44,45,46,47,48,49,
        50,51,52,53,54,55,56,57,58,59,
        60,61,62,63,64,65,66,67,68,69,
        70,71,72,73,74,75,76,77,78,79,
        80,81,82,82,83,84,85,85,86,87,
        */
        88, 90, 93, 95, 97, 99, 101, 103, 106, 108,
        110, 113, 115, 118, 120, 123, 125, 128, 130, 133,
        136, 138, 141, 144, 147, 149, 152, 155, 158, 161,
        164, 167, 171, 174, 177, 180, 183, 187, 190, 194,
        197, 200, 204, 208, 211, 215, 218, 222, 226, 230,
        234, 237, 241, 245, 249, 254, 258, 262, 266, 270,
        275, 279, 283, 288, 292, 297, 301, 306, 311, 315,
        320, 325, 330, 335, 340, 345, 350, 355, 360, 365,
        370, 376, 381, 386, 392, 397, 403, 408, 414, 420,
        425, 431, 437, 443, 449, 455, 461, 467, 473, 480,
        486, 492, 499, 505, 512, 518, 525, 532, 538, 545,
        552, 559, 566, 573, 580, 587, 594, 601, 609, 616,
        624, 631, 639, 646, 654, 662, 669, 677, 685, 693,
        701, 709, 717, 726, 734, 742, 751, 759, 768, 776,
        785, 794, 802, 811, 820, 829, 838, 847, 857, 866,
        875, 885, 894, 903, 913, 923, 932, 942, 952, 962,
        972, 982, 992, 1002, 1013, 1023
};


const unsigned char cie_12b[256] = {
        0, 2, 4, 5, 7, 9, 11, 12, 14, 16,
        18, 20, 21, 23, 25, 27, 28, 30, 32, 34,
        36, 37, 39, 41, 43, 45, 47, 49, 52, 54,
        56, 59, 61, 64, 66, 69, 72, 75, 77, 80,
        83, 87, 90, 93, 96, 100, 103, 107, 111, 115,
        118, 122, 126, 131, 135, 139, 144, 148, 153, 157,
        162, 167, 172, 177, 182, 187, 193, 198, 204, 209,
        215, 221, 227, 233, 239, 246, 252, 259, 265, 272,
        279, 286, 293, 300, 308, 315, 323, 330, 338, 346,
        354, 362, 371, 379, 388, 396, 405, 414, 423, 432,
        442, 451, 461, 470, 480, 490, 501, 511, 521, 532,
        543, 553, 564, 576, 587, 598, 610, 622, 634, 646,
        658, 670, 683, 695, 708, 721, 734, 748, 761, 775,
        788, 802, 816, 831, 845, 860, 874, 889, 904, 920,
        935, 951, 966, 982, 999, 1015, 1031, 1048, 1065, 1082,
        1099, 1116, 1134, 1152, 1170, 1188, 1206, 1224, 1243, 1262,
        1281, 1300, 1320, 1339, 1359, 1379, 1399, 1420, 1440, 1461,
        1482, 1503, 1525, 1546, 1568, 1590, 1612, 1635, 1657, 1680,
        1703, 1726, 1750, 1774, 1797, 1822, 1846, 1870, 1895, 1920,
        1945, 1971, 1996, 2022, 2048, 2074, 2101, 2128, 2155, 2182,
        2209, 2237, 2265, 2293, 2321, 2350, 2378, 2407, 2437, 2466,
        2496, 2526, 2556, 2587, 2617, 2648, 2679, 2711, 2743, 2774,
        2807, 2839, 2872, 2905, 2938, 2971, 3005, 3039, 3073, 3107,
        3142, 3177, 3212, 3248, 3283, 3319, 3356, 3392, 3429, 3466,
        3503, 3541, 3578, 3617, 3655, 3694, 3732, 3772, 3811, 3851,
        3891, 3931, 3972, 4012, 4054, 4095,
};



typedef struct {
  volatile uint8_t val;
  uint8_t          pin;
} led_t;

typedef struct {
  led_t r;
  led_t g;
  led_t b;
} rgb_t;

struct {
  volatile uint8_t rgb_frame;
  volatile uint8_t hello_frame;
} usb_state;

volatile int8_t disabled = -1;
static rgb_t led;

void set_rgb(uint8_t r, uint8_t g, uint8_t b) {
  led.r.val = r;
  led.g.val = g;
  led.b.val = b;

  Timer1.setPwmDuty(led.r.pin, cie_10b[led.r.val]); 
  Timer1.setPwmDuty(led.g.pin, cie_10b[led.g.val]); 
  Timer1.setPwmDuty(led.b.pin, cie_10b[led.b.val]);
}

uint8_t toggle_internal_status() {
  static uint8_t stat = 0;
  stat = stat+1 % 2;
  
  digitalWrite(LED_BUILTIN, stat); 
}



void status_indicator() {
  int off = digitalRead(12);

  Serial.println(off);
 
  if(off) {
    //DISABLE pin
    if(disabled != 1) {
      Serial.println(F("disable"));
      Timer3.stop();
      Timer3.initialize(100);
      Timer3.start();
      Timer3.pwm(9, 5);

      set_rgb(0,0,0);
    }
    disabled = 1;
  }
  else {
    if(disabled != 0) {
      Serial.println(F("enable"));
      Timer3.stop();
      Timer3.initialize(1000000);
      Timer3.start();
      Timer3.pwm(9, 256);

      //set_rgb(2,2,2);
    }
    disabled = 0;
    
    if(usb_state.rgb_frame) {
        Timer3.setPwmDuty(9, 1022);
    }
    else if(usb_state.hello_frame) {
      Timer3.setPwmDuty(9, 512);
    }
    else {
      Timer3.setPwmDuty(9, 100);
    }
  }
}

void setup(void)
{ 

  Serial.begin(9600);
  
  Timer1.initialize(500);
  Timer1.start();

  Timer3.attachInterrupt(status_indicator);
  status_indicator();
  
  led.r.pin = 15;
  led.g.pin = 14;
  led.b.pin = 4;
  pinMode(led.r.pin, OUTPUT);
  pinMode(led.g.pin, OUTPUT);
  pinMode(led.b.pin, OUTPUT);
  Timer1.pwm(led.r.pin, 0);
  Timer1.pwm(led.g.pin, 0);
  Timer1.pwm(led.b.pin, 0);
  
  set_rgb(4,4,4);

  usb_state.rgb_frame = 0;
  usb_state.hello_frame = 0;
  
  //Serial.begin(9600);
  //Serial.println(F("RawHID Example"));

  toggle_internal_status();

  
}

void handleUsbHID(void) {
  
  static byte buffer[64];
  
  int n = RawHID.recv(buffer, 0); // 0 timeout = do not wait
  if (n > 0) {

    /*
    Serial.print(F("Received packet, first 4 bytes: "));
    Serial.print((uint8_t)buffer[0]);
    Serial.print(F(","));
    Serial.print((uint8_t)buffer[1]);
    Serial.print(F(","));
    Serial.print((uint8_t)buffer[2]);
    Serial.print(F(","));
    Serial.println((uint8_t)buffer[3]);
    */
    
    //buffer[0] is always 42. something about it not being 0 is important...

    if(buffer[0]==42) { //rgb frame
      set_rgb(buffer[1],buffer[2],buffer[3]);
      usb_state.hello_frame=0;
      usb_state.rgb_frame=1;
    }
    else if(buffer[0]=62) {
      //hello frame
      usb_state.rgb_frame=0;
      usb_state.hello_frame=1;
    }
    
    //toggle_status();
  }
}


static uint8_t use_cie1931 = 0;

void loop(void)
{
  if(disabled) {
    delay(200);
  }
  else {
    handleUsbHID();
  }

  /*
  if(use_cie1931) {
    analogWrite(led.r.pin, cie1931[led.r.val]);
    analogWrite(led.g.pin, cie1931[led.g.val]);
    analogWrite(led.b.pin, cie1931[led.b.val]);
  }
  else {
    analogWrite(led.r.pin, led.r.val);
    analogWrite(led.g.pin, led.g.val);
    analogWrite(led.b.pin, led.b.val);
  }
  */
}

