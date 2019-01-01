Version 4
SymbolType BLOCK
TEXT 32 32 LEFT 4 div_8_dot_8_nodsp
RECTANGLE Normal 32 32 608 576
LINE Normal 0 80 32 80
PIN 0 80 LEFT 36
PINATTR PinName s_axis_dividend_tvalid
PINATTR Polarity IN
LINE Normal 0 112 32 112
PIN 0 112 LEFT 36
PINATTR PinName s_axis_dividend_tready
PINATTR Polarity OUT
LINE Wide 0 144 32 144
PIN 0 144 LEFT 36
PINATTR PinName s_axis_dividend_tdata[23:0]
PINATTR Polarity IN
LINE Normal 0 272 32 272
PIN 0 272 LEFT 36
PINATTR PinName s_axis_divisor_tvalid
PINATTR Polarity IN
LINE Normal 0 304 32 304
PIN 0 304 LEFT 36
PINATTR PinName s_axis_divisor_tready
PINATTR Polarity OUT
LINE Wide 0 336 32 336
PIN 0 336 LEFT 36
PINATTR PinName s_axis_divisor_tdata[15:0]
PINATTR Polarity IN
LINE Normal 0 464 32 464
PIN 0 464 LEFT 36
PINATTR PinName aclk
PINATTR Polarity IN
LINE Normal 640 80 608 80
PIN 640 80 RIGHT 36
PINATTR PinName m_axis_dout_tvalid
PINATTR Polarity OUT
LINE Wide 640 144 608 144
PIN 640 144 RIGHT 36
PINATTR PinName m_axis_dout_tdata[39:0]
PINATTR Polarity OUT

