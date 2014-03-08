//
// 
// Data layout.
// 
// Local storage. Starts at offset 0 of the internal PRU memory bank. Initial values are set by the host
// program. Contains the following blocks:
// 
// Offset       Length  Value         Name       Description
// ------       ------  -----         ----       -----------
// 0x0000            4  0xbeef1965    EYE        Eyecatcher constant 0xbeef1965
// 0x0004            4  0x00000000    TICKS      Number of capture ticks. Incremented each time ADC capture runs (200K times per sec, approx)
// 0x0008            4  0x00000000    FLAGS      Execution flags (bit mapped)
// 0x000c            4  0x00000000    SCOPE_OUT  Address of the DDR memory buffer where to store OSCILLOSCOPE captured values
// 0x0010            4  0x00000000    SCHOPE_OFF Offset to use for OSCILLOSCOPE capture
// 0x0014            4  0x00000000    SCOPE_LEN  How many values to capture in OSCILLOSCOPE mode
// 0x0018            4  0x00000000               Reserved
// 0x001c            3  0x000000                 Reserved
// 0x001f            1  0x01          EMA_POW    Exponent to use for EMA-averaging: ema_value += (value - ema_value / 2^EMA_POW)
// 0x0020            4  0x00000000    AIN0_EMA   Value (optionally smoothened via EMA) of the channel AIN0
// 0x0024            4  0x00000000    AIN1_EMA   Value (optionally smoothened via EMA) of the channel AIN1
// 0x0028            4  0x00000000    AIN2_EMA   Value (optionally smoothened via EMA) of the channel AIN2
// 0x002c            4  0x00000000    AIN3_EMA   Value (optionally smoothened via EMA) of the channel AIN3
// 0x0030            4  0x00000000    AIN4_EMA   Value (optionally smoothened via EMA) of the channel AIN4
// 0x0034            4  0x00000000    AIN5_EMA   Value (optionally smoothened via EMA) of the channel AIN5
// 0x0038            4  0x00000000    AIN6_EMA   Value (optionally smoothened via EMA) of the channel AIN6
// 0x003c            4  0x00000000    AIN7_EMA   Value (optionally smoothened via EMA) of the channel AIN7

.origin 0
.entrypoint START

#define PRU0_ARM_INTERRUPT 19

#define ADC_BASE            0x44e0d000

#define CONTROL         0x0040
#define STEP1           0x0064
#define DELAY1          0x0068
#define STATUS          0x0044
#define STEPCONFIG      0x0054
#define FIFO0COUNT      0x00e4

#define ADC_FIFO0DATA       (ADC_BASE + 0x0100)

// Register allocations
#define adc_      r6
#define fifo0data r7
#define out_buff  r8
#define locals    r9

#define value     r10
#define channel   r11
#define ema       r12
#define encoders  r13

#define tmp0      r1
#define tmp1      r2
#define tmp2      r3
#define tmp3      r4
#define tmp4      r5

START:
    LBCO r0, C4, 4, 4					// Load Bytes Constant Offset (?)
    CLR  r0, r0, 4						// Clear bit 4 in reg 0
    SBCO r0, C4, 4, 4					// Store Bytes Constant Offset

	MOV adc_, ADC_BASE
	MOV fifo0data, ADC_FIFO0DATA
	MOV locals, 0

	MOV tmp0, 0xffffffff
	SBBO tmp0, locals, 0, 4
	JMP QUIT
	
	LBBO tmp0, locals, 0, 4				// check eyecatcher
	MOV tmp1, 0xbeef1965				//
	QBNE QUIT, tmp0, tmp1				// bail out if does not match



	MOV out_buff, 0x80001000
	LBBO ema, locals, 0x1c, 4
	LBBO encoders, locals, 0x40, 4
	
	// Disable ADC
	LBBO tmp0, adc_, CONTROL, 4
	MOV  tmp1, 0x1
	NOT  tmp1, tmp1
	AND  tmp0, tmp0, tmp1
	SBBO tmp0, adc_, CONTROL, 4
	
	// Configure STEPCONFIG registers for all 8 channels
    MOV tmp0, STEP1
	MOV tmp1, 0
	MOV tmp2, 0
FILL_STEPS:
    LSL tmp3, tmp1, 19
    SBBO tmp3, adc_, tmp0, 4
    ADD tmp0, tmp0, 4
    SBBO tmp2, adc_, tmp0, 4
    ADD tmp1, tmp1, 1
    ADD tmp0, tmp0, 4
    QBNE FILL_STEPS, tmp1, 8

	// Enable ADC with the desired mode (make STEPCONFIG registers writable, use tags, enable)
	LBBO tmp0, adc_, CONTROL, 4
	OR   tmp0, tmp0, 0x7
	SBBO tmp0, adc_, CONTROL, 4
	
	MOV tmp0, 0xffffffff
	SBBO tmp0, locals, 0, 4
	JMP QUIT

CAPTURE:
	
	MOV tmp0, 0x1fe	
	SBBO tmp0, adc_, STEPCONFIG, 4   // write STEPCONFIG register (this triggers capture)

	// check for exit flag
	LBBO tmp0, locals, 0x08, 4   // read runtime flags
	QBNE QUIT, tmp0.b0, 0
	
	// check for oscilloscope mode
	LBBO tmp0, locals, 0x14, 4
	QBEQ NO_SCOPE, tmp0, 0
	
	SUB tmp0, tmp0, 4
	SBBO tmp0, locals, 0x14, 4
	LBBO tmp0, locals, 0x10, 4
	LBBO tmp0, locals, tmp0, 4
	SBBO tmp0, out_buff, 0, 4
	ADD out_buff, out_buff, 4

NO_SCOPE:

    // increment ticks
	LBBO tmp0, locals, 0x04, 4
	ADD  tmp0, tmp0, 1
	SBBO tmp0, locals, 0x04, 4
	
	// increment encoder ticks
	LBBO tmp0, locals, 0x5c, 4
	ADD  tmp0, tmp0, 1
	SBBO tmp0, locals, 0x5c, 4

	LBBO tmp0, locals, 0x7c, 4
	ADD  tmp0, tmp0, 1
	SBBO tmp0, locals, 0x7c, 4

WAIT_FOR_FIFO0:
    LBBO tmp0, adc_, FIFO0COUNT, 4
    QBNE WAIT_FOR_FIFO0, tmp0, 8

READ_ALL_FIFO0:                  // lets read all fifo content and dispatch depending on pin type
    LBBO value, fifo0data, 0, 4
    LSR  channel, value, 16
    AND channel, channel, 0xf
    MOV tmp1, 0xfff
    AND value, value, tmp1

    // here we have true captured value and channel
    QBNE NOT_ENC0, encoders.b0, channel
    MOV channel, 0
    CALL PROCESS
    JMP NEXT_CHANNEL
NOT_ENC0:
	QBNE NOT_ENC1, encoders.b1, channel
	MOV channel, 1
	CALL PROCESS
	JMP NEXT_CHANNEL
NOT_ENC1:

	LSL tmp1, channel, 2       // to byte offset
	ADD tmp1, tmp1, 0x20       // base of the EMA values
	LBBO tmp2, locals, tmp1, 4
	LSR tmp3, tmp2, ema
	SUB tmp3, value, tmp3
	ADD tmp2, tmp2, tmp3
	SBBO tmp2, locals, tmp1, 4

NEXT_CHANNEL:
    SUB tmp0, tmp0, 1
    QBNE READ_ALL_FIFO0, tmp0, 0
    
    JMP CAPTURE

QUIT:
    MOV R31.b0, PRU0_ARM_INTERRUPT+16   // Send notification to Host for program completion
HALT

PROCESS:                        // lets process captured data. Type of processing depends on the pin type: average or wheel encoder
	LSL channel, channel, 5
	ADD channel, channel, 0x44
	LBBO &tmp1, locals, channel, 16 // load tmp1-tmp4 (threshold, raw, min, max)
	MOV tmp2, value
	MIN tmp3, tmp3, value
	MAX tmp4, tmp4, value
	SBBO &tmp1, locals, channel, 16 // store min/max etc
	ADD tmp2, tmp3, tmp1            // tmp2 = min + threshold
	QBLT TOHIGH, value, tmp2
	ADD tmp2, value, tmp1           // tmp2 = value + threshold
	QBLT TOLOW, tmp4, tmp2

	RET

TOLOW:
	ADD channel, channel, 8
	MOV tmp2, value
	MOV tmp3, value
	SBBO &tmp2, locals, channel, 8
	
	ADD channel, channel, 8
	LBBO &tmp2, locals, channel, 12
	ADD tmp2, tmp2, 1
	MOV tmp3, tmp4
	MOV tmp4, 0
	SBBO &tmp2, locals, channel, 12
	RET
	
TOHIGH:
	ADD channel, channel, 8
	MOV tmp2, value
	MOV tmp3, value
	SBBO &tmp2, locals, channel, 8
	RET