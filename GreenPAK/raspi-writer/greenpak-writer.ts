import i2c from "i2c-bus"
import fs from "fs"

//var i2c = require('i2c-bus')
//var intelhex = require('intel-hex')
//var fs = require('fs')
//var timers = require('timers/promises')

const intelhex = require("intel-hex");

function toHex(v: number) {
    return (v).toString(16).padStart(2, '0')
}

const DEVICE_NUMBER = 1;
const TARGET_IC_ADDR = 0x0a;

var i2c1 = i2c.openSync(DEVICE_NUMBER);

var readBuf = Buffer.alloc(0xff);
//i2c1.i2cReadSync(TARGET_IC_ADDR, readBuf.length, readBuf);
//console.log(readBuf);

//var value = 
i2c1.i2cReadSync(TARGET_IC_ADDR, readBuf.length, readBuf)
//console.log(readBuf)

var readBuf16 = Buffer.alloc(0x10);
for (let i=0; i < 256; i+=16) {
    i2c1.readI2cBlockSync(TARGET_IC_ADDR, i, readBuf16.length, readBuf16)
    var text =''
    readBuf16.forEach( (v,i, a) => {
        text += toHex(v) + " "
    })
    console.log(text)
}

// intel hexファイルを読み込む

var hexfile = fs.readFileSync("X68KeplerX-BusController.hex")
//console.log(hexfile)

var data = intelhex.parse(hexfile)
console.log("startSegmentAddress: "+data.startSegmentAddress)
console.log("startLinearAddress : "+data.startLinearAddress)
//console.log(data.data)
var line = ''
data.data.forEach( (v:number,i:number, a:any) => {
    line += toHex(v)+" "
    if (i%16 == 15) {
        console.log(line)
        line = ''
    }
}
)

if (data.data.length != 256) {
    process.exit(-1)    
}

//for (let i=0; i < 256; i++) {
//    i2c.i2cWriteSync(TARGET_IC_ADDR, data.data[i])
//}

function wait(ms: number) {
    const start = Date.now();
    while (true) {
      if (Date.now() - start >= ms) {
        return;
      }
    }
  }

var eraseBuf = Buffer.alloc(2);
for(let i=0; i<16;i++) {
    console.log("eraseing: "+i)
//    eraseBuf[0] = 0xE3
//    i2c1.i2cWriteSync(TARGET_IC_ADDR-1,1,eraseBuf)
//    wait(100)
//    eraseBuf[0] = 0x80 + i
//    i2c1.i2cWriteSync(TARGET_IC_ADDR-1,1,eraseBuf)
//    eraseBuf[0] = 0x80 +i
//    i2c1.writeI2cBlockSync(TARGET_IC_ADDR-1,0xe3,1, eraseBuf)
//    i2c1.writeByteSync(TARGET_IC_ADDR-1,0xe3,0x80+i)

    try {
      eraseBuf[0] = 0xE3
      eraseBuf[1] = 0x80 +i
      i2c1.i2cWriteSync(TARGET_IC_ADDR-1,2,eraseBuf)
    } catch(e) {
        console.log("error but it can be ignored")
    }
	wait(1000)
}

var writeBuf = Buffer.alloc(16);
for(let i=0; i<256;i+=16) {
    console.log("writing: "+i)
    for(let j=0;j<16;j++) {
        writeBuf[j] = data.data[i+j]
    }
    i2c1.writeI2cBlockSync(TARGET_IC_ADDR,i,16, writeBuf)
    wait(1000)
}
//i2c1.i2cWriteSync(TARGET_IC_ADDR, data.data.length, data.data)

//reset
try {
    eraseBuf[0] = 0xc8
    eraseBuf[1] = 0x02
    i2c1.i2cWriteSync(TARGET_IC_ADDR-1,2,eraseBuf)
} catch(e) {
    console.log("error but it can be ignored")
}
