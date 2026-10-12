`timescale 1ns / 1ps

`include "algo_cfg.vh"

module img_core #(
    parameter IMG_W = 128,      
    parameter IMG_H = 128,      
    parameter OUT_W = 128,      
    parameter OUT_H = 128,      
    parameter AW    = 14,       
    parameter OAW   = 16        
)(
    input  wire           clk,
    input  wire           rst_n,

    
    input  wire           we,
    input  wire [AW-1:0]  waddr,
    input  wire [23:0]    wdata,

    
    input  wire           start,      
    output reg            busy,       
    output reg            done,       

    
    input  wire [OAW-1:0] raddr,
    output wire [23:0]    rdata,

    
    output wire [OAW-1:0] prog_addr,  
    output wire [31:0]    hit_cnt     
);

    localparam NPIX  = IMG_W * IMG_H;      
    localparam NPOUT = OUT_W * OUT_H;      

    
    `ifdef ALGO_SCALE_UP2
        localparam integer CENTER_SHIFT = -1;
    `elsif ALGO_SCALE_DOWN2
        localparam integer CENTER_SHIFT = 1;
    `elsif ALGO_SCALE_DOWN2_ALIAS
        localparam integer CENTER_SHIFT = 1;
    `elsif ALGO_TRAPEZOID
        localparam integer CENTER_SHIFT = 2;   
    `else
        localparam integer CENTER_SHIFT = 0;
    `endif

    
    localparam S_IDLE = 3'd0,
               S_RD   = 3'd1,   
               S_WR   = 3'd2,   
               S_NEXT = 3'd3,   
               S_DONE = 3'd4;

    reg [2:0] state;

    
    reg [23:0] in_ram  [0:NPIX-1];
    reg [23:0] out_ram [0:NPOUT-1];

    
    integer ki;
    initial begin
        for (ki = 0; ki < NPIX;  ki = ki + 1) in_ram[ki]  = 24'h000000;
        for (ki = 0; ki < NPOUT; ki = ki + 1) out_ram[ki] = 24'h000000;
    end

    always @(posedge clk) begin
        if (we) in_ram[waddr] <= wdata;
    end

    
    reg           out_we;
    reg [OAW-1:0] out_waddr;
    reg [23:0]    out_wdata;
    always @(posedge clk) begin
        if (out_we) out_ram[out_waddr] <= out_wdata;
    end

    
    reg [23:0] rdata_r;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rdata_r <= 24'd0;
        else        rdata_r <= out_ram[raddr];
    end
    assign rdata = rdata_r;

    
    reg [OAW-1:0] ox, oy;          
    reg [AW-1:0]  cx, cy;          

    
    wire [6:0] trap_w = 7'd64 + oy[6:1];        
    wire [5:0] trap_l = 6'd32 - oy[7:2];        
    wire [6:0] trap_f = (ox * trap_w) & 7'h7F;  

    always @* begin
        if      (CENTER_SHIFT == -1) begin cx = ox >> 1; cy = oy >> 1; end  
        else if (CENTER_SHIFT ==  1) begin cx = ox << 1; cy = oy << 1; end  
        else if (CENTER_SHIFT ==  2) begin
            
            cx = ((ox * trap_w) >> 7) + trap_l;
            cy = oy;
        end
        else                         begin cx = ox;      cy = oy;      end  
    end

    
    wire [AW-1:0] cm1 = (cx == {AW{1'b0}}) ? {AW{1'b0}} : (cx - 1'b1);
    wire [AW-1:0] cp1 = (cx >= IMG_W-1)    ? (IMG_W-1)  : (cx + 1'b1);
    wire [AW-1:0] rm1 = (cy == {AW{1'b0}}) ? {AW{1'b0}} : (cy - 1'b1);
    wire [AW-1:0] rp1 = (cy >= IMG_H-1)    ? (IMG_H-1)  : (cy + 1'b1);

    
    wire [31:0] row_m = rm1 * IMG_W;
    wire [31:0] row_c = cy  * IMG_W;
    wire [31:0] row_p = rp1 * IMG_W;

    
    wire [AW-1:0] a0 = row_m[AW-1:0] + cm1;   
    wire [AW-1:0] a1 = row_m[AW-1:0] + cx;    
    wire [AW-1:0] a2 = row_m[AW-1:0] + cp1;   
    wire [AW-1:0] a3 = row_c[AW-1:0] + cm1;   
    wire [AW-1:0] a4 = row_c[AW-1:0] + cx;    
    wire [AW-1:0] a5 = row_c[AW-1:0] + cp1;   
    wire [AW-1:0] a6 = row_p[AW-1:0] + cm1;   
    wire [AW-1:0] a7 = row_p[AW-1:0] + cx;    
    wire [AW-1:0] a8 = row_p[AW-1:0] + cp1;   

    
    reg [3:0]    k;
    reg [AW-1:0] rd_addr;

    always @* begin
        case (k)
            4'd0: rd_addr = a0;
            4'd1: rd_addr = a1;
            4'd2: rd_addr = a2;
            4'd3: rd_addr = a3;
            4'd4: rd_addr = a4;
            4'd5: rd_addr = a5;
            4'd6: rd_addr = a6;
            4'd7: rd_addr = a7;
            4'd8: rd_addr = a8;
            default: rd_addr = a4;      
        endcase
    end

    
    reg [23:0] in_pix;
    reg [3:0]  kq;
    reg [23:0] win [0:8];

    
    integer wi;
    initial begin
        in_pix = 24'd0;
        kq     = 4'd0;
        for (wi = 0; wi < 9; wi = wi + 1) win[wi] = 24'd0;
    end

    integer wj;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_pix <= 24'd0;
            kq     <= 4'd0;
            for (wj = 0; wj < 9; wj = wj + 1) win[wj] <= 24'd0;
        end
        else begin
            in_pix <= in_ram[rd_addr];
            kq     <= k;
            
            if (kq <= 4'd8) win[kq] <= in_pix;
        end
    end

    
    wire [23:0] algo_pix;
    wire        algo_hit;

    img_algo u_algo (
        .w_tl (win[0]), .w_t (win[1]), .w_tr (win[2]),
        .w_l  (win[3]), .w_c (win[4]), .w_r  (win[5]),
        .w_bl (win[6]), .w_b (win[7]), .w_br (win[8]),
        .f    (trap_f),
        .pix_out (algo_pix),
        .hit     (algo_hit)
    );

    
    wire [31:0] out_idx = oy * OUT_W + ox;
    assign prog_addr = out_idx[OAW-1:0];

    reg [31:0] hit_r;
    reg        clr_hit;

    always @(posedge clk or negedge rst_n) begin
        if      (!rst_n)                    hit_r <= 32'd0;
        else if (clr_hit)                   hit_r <= 32'd0;
        else if (state == S_WR && algo_hit) hit_r <= hit_r + 32'd1;
    end
    assign hit_cnt = hit_r;

    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            k         <= 4'd0;
            ox        <= {OAW{1'b0}};
            oy        <= {OAW{1'b0}};
            busy      <= 1'b0;
            done      <= 1'b0;
            out_we    <= 1'b0;
            out_waddr <= {OAW{1'b0}};
            out_wdata <= 24'd0;
            clr_hit   <= 1'b0;
        end
        else begin
            done    <= 1'b0;
            clr_hit <= 1'b0;
            out_we  <= 1'b0;

            case (state)
                
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        ox      <= {OAW{1'b0}};
                        oy      <= {OAW{1'b0}};
                        k       <= 4'd0;
                        clr_hit <= 1'b1;          
                        busy    <= 1'b1;
                        state   <= S_RD;
                    end
                end

                
                S_RD: begin
                    if (k < 4'd9) k     <= k + 4'd1;
                    else          state <= S_WR;   
                end

                
                S_WR: begin
                    out_we    <= 1'b1;
                    out_waddr <= out_idx[OAW-1:0];
                    out_wdata <= algo_pix;
                    state     <= S_NEXT;
                end

                
                S_NEXT: begin
                    k <= 4'd0;
                    if (ox == OUT_W-1) begin
                        ox <= {OAW{1'b0}};
                        if (oy == OUT_H-1) state <= S_DONE;   
                        else begin
                            oy    <= oy + 1'b1;
                            state <= S_RD;
                        end
                    end
                    else begin
                        ox    <= ox + 1'b1;
                        state <= S_RD;
                    end
                end

                
                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;        
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
