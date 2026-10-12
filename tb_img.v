`timescale 1ns / 1ps

`include "algo_cfg.vh"
`include "img_param.vh"      

`ifndef OUT_DIM
    `define OUT_DIM "img_out_dim.txt"
`endif

module tb_img;

    
    localparam IMG_W = `IMG_W;
    localparam IMG_H = `IMG_H;
    localparam NPIX  = IMG_W * IMG_H;
    localparam AW    = 14;      
    localparam OAW   = 16;      

  
    `ifdef ALGO_SCALE_UP2
        localparam OUT_W = IMG_W * 2;
        localparam OUT_H = IMG_H * 2;
    `elsif ALGO_SCALE_DOWN2
        localparam OUT_W = IMG_W / 2;
        localparam OUT_H = IMG_H / 2;
    `elsif ALGO_SCALE_DOWN2_ALIAS
        localparam OUT_W = IMG_W / 2;
        localparam OUT_H = IMG_H / 2;
    `else
        localparam OUT_W = IMG_W;
        localparam OUT_H = IMG_H;
    `endif
    localparam NPOUT = OUT_W * OUT_H;

    
    `ifdef ALGO_INVERT
        localparam ALGO_NAME = "ALGO_INVERT";
    `elsif ALGO_GRAY
        localparam ALGO_NAME = "ALGO_GRAY";
    `elsif ALGO_BINARIZE
        localparam ALGO_NAME = "ALGO_BINARIZE";
    `elsif ALGO_RGB_SWAP
        localparam ALGO_NAME = "ALGO_RGB_SWAP";
    `elsif ALGO_BRIGHT
        localparam ALGO_NAME = "ALGO_BRIGHT";
    `elsif ALGO_RED_DETECT
        localparam ALGO_NAME = "ALGO_RED_DETECT";
    `elsif ALGO_DILATE
        localparam ALGO_NAME = "ALGO_DILATE";
    `elsif ALGO_ERODE
        localparam ALGO_NAME = "ALGO_ERODE";
    `elsif ALGO_SHARPEN
        localparam ALGO_NAME = "ALGO_SHARPEN";
    `elsif ALGO_SCALE_UP2
        localparam ALGO_NAME = "ALGO_SCALE_UP2";
    `elsif ALGO_SCALE_DOWN2
        localparam ALGO_NAME = "ALGO_SCALE_DOWN2";
    `elsif ALGO_SCALE_DOWN2_ALIAS
        localparam ALGO_NAME = "ALGO_SCALE_DOWN2_ALIAS";
    `elsif ALGO_TRAPEZOID
        localparam ALGO_NAME = "ALGO_TRAPEZOID";
    `else
        localparam ALGO_NAME = "PASSTHROUGH";
    `endif

    
    reg           clk;
    reg           rst_n;
    reg           we;
    reg  [AW-1:0] waddr;
    reg  [23:0]   wdata;
    reg  [OAW-1:0] raddr;
    wire [23:0]   rdata;
    reg           start;
    wire          done;
    wire          busy;
    wire [OAW-1:0] prog_addr;
    wire [31:0]   hit_cnt;

    
    reg [23:0] mem [0:NPIX-1];

    integer      fd_out, fd_dim;
    integer      i;
    reg  [31:0]  fout;          
    reg  [31:0]  hit_num;

    
    img_core #(
        .IMG_W (IMG_W),
        .IMG_H (IMG_H),
        .OUT_W (OUT_W),
        .OUT_H (OUT_H),
        .AW    (AW),
        .OAW   (OAW)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .we        (we),
        .waddr     (waddr),
        .wdata     (wdata),
        .start     (start),
        .busy      (busy),
        .done      (done),
        .raddr     (raddr),
        .rdata     (rdata),
        .prog_addr (prog_addr),
        .hit_cnt   (hit_cnt)
    );

    
    initial clk = 1'b0;
    always #5 clk = ~clk;

    
    initial begin
        #200_000_000;
        $display("[TB] TIMEOUT (>200ms) -- design seems stuck, check FSM");
        $finish;
    end

    
    initial begin
        
        rst_n   = 1'b0;
        we      = 1'b0;
        waddr   = {AW{1'b0}};
        wdata   = 24'd0;
        raddr   = {OAW{1'b0}};
        start   = 1'b0;
        fout    = 32'd0;
        hit_num = 32'd0;
        i       = 0;
        fd_out  = 0;
        fd_dim  = 0;

        $display("=================================================");
        $display("[TB] algorithm  = %0s", ALGO_NAME);
        $display("[TB] input  size = %0d x %0d  (%0d pixels)", IMG_W, IMG_H, NPIX);
        $display("[TB] output size = %0d x %0d  (%0d pixels)", OUT_W, OUT_H, NPOUT);
        $display("=================================================");

        
        $readmemh(`IN_MEM, mem);
        $display("[TB] loaded input: %0s", `IN_MEM);

       
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        $display("[TB] self-check: out_ram[0] = %h (expect 000000)", rdata);

        
        for (i = 0; i < NPIX; i = i + 1) begin
            @(negedge clk);
            we    = 1'b1;
            waddr = i[AW-1:0];
            wdata = mem[i];
        end
        @(negedge clk);
        we = 1'b0;
        $display("[TB] wrote %0d pixels into in_ram", NPIX);

        
        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;
        wait (done == 1'b1);
        @(negedge clk);

        hit_num = hit_cnt;
        
        $display("[TB] DONE. simulation time = %0d ns, hit = %0d pixels", $time, hit_num);

        
        fd_out = $fopen(`OUT_MEM, "w");
        if (fd_out == 0) begin
            $display("[TB] ERROR: cannot open %0s for writing", `OUT_MEM);
            $finish;
        end

        for (i = 0; i < NPOUT; i = i + 1) begin
            @(negedge clk);
            raddr = i[OAW-1:0];         
            @(negedge clk);             
            fout = rdata;
            if (i < 4)
                $display("[TB] out[%0d] = %06x", i, fout);
            $fwrite(fd_out, "%06x\n", fout);
        end
        $fclose(fd_out);
        $display("[TB] wrote %0d pixels to %0s", NPOUT, `OUT_MEM);

        
        fd_dim = $fopen(`OUT_DIM, "w");
        if (fd_dim != 0) begin
            $fwrite(fd_dim, "%0d %0d\n", OUT_W, OUT_H);
            $fclose(fd_dim);
            $display("[TB] wrote output size to %0s", `OUT_DIM);
        end

        $display("=================================================");
        $finish;
    end

endmodule
