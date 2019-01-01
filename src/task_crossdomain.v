// taken from: https://www.fpga4fun.com/CrossClockDomain3.html
// copyrighted fpga4fun.com & KNJN LLC.

module task_crossdomain(
    input clka,
    input taskstart_clka,
    output taskbusy_clka, taskdone_clka,

    input clkb,
    output taskstart_clkb, taskbusy_clkb,
    input taskdone_clkb
);

reg FlagToggle_clkA = 0;
reg FlagToggle_clkB = 0;
reg Busyhold_clkB = 0;
reg [2:0] SyncA_clkB = 0;
reg [2:0] SyncB_clkA = 0;

always @(posedge clka) FlagToggle_clkA <= FlagToggle_clkA ^ (taskstart_clka & ~taskbusy_clka);

always @(posedge clkb) SyncA_clkB <= {SyncA_clkB[1:0], FlagToggle_clkA};
assign taskstart_clkb = (SyncA_clkB[2] ^ SyncA_clkB[1]);
assign taskbusy_clkb = taskstart_clkb | Busyhold_clkB;
always @(posedge clkb) Busyhold_clkB <= ~taskdone_clkb & taskbusy_clkb;
always @(posedge clkb) if(taskbusy_clkb & taskdone_clkb) FlagToggle_clkB <= FlagToggle_clkA;

always @(posedge clka) SyncB_clkA <= {SyncB_clkA[1:0], FlagToggle_clkB};
assign taskbusy_clka = FlagToggle_clkA ^ SyncB_clkA[2];
assign taskdone_clka = SyncB_clkA[2] ^ SyncB_clkA[1];
endmodule
