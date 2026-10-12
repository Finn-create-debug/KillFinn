`timescale 1ns / 1ps

`include "algo_cfg.vh"

module img_algo (
    input  wire [23:0] w_tl, w_t, w_tr,   
    input  wire [23:0] w_l,  w_c, w_r,    
    input  wire [23:0] w_bl, w_b, w_br,   
    input  wire [6:0]  f,                 
    output reg  [23:0] pix_out,           
    output reg         hit                
);

    
    function [7:0] gray_of;
        input [23:0] p;
        reg   [31:0] s;
        begin
            s       = p[23:16] * 77 + p[15:8] * 150 + p[7:0] * 29;
            gray_of = s[15:8];
        end
    endfunction

    
    function [7:0] sat_add;
        input [7:0] v;
        input [7:0] d;
        reg   [8:0] s;
        begin
            s       = {1'b0, v} + {1'b0, d};
            sat_add = s[8] ? 8'hFF : s[7:0];
        end
    endfunction

    
    function [7:0] max9;
        input [7:0] v0, v1, v2, v3, v4, v5, v6, v7, v8;
        reg   [7:0] m;
        begin
            m = v0;
            if (v1 > m) m = v1;
            if (v2 > m) m = v2;
            if (v3 > m) m = v3;
            if (v4 > m) m = v4;
            if (v5 > m) m = v5;
            if (v6 > m) m = v6;
            if (v7 > m) m = v7;
            if (v8 > m) m = v8;
            max9 = m;
        end
    endfunction

    
    function [7:0] min9;
        input [7:0] v0, v1, v2, v3, v4, v5, v6, v7, v8;
        reg   [7:0] m;
        begin
            m = v0;
            if (v1 < m) m = v1;
            if (v2 < m) m = v2;
            if (v3 < m) m = v3;
            if (v4 < m) m = v4;
            if (v5 < m) m = v5;
            if (v6 < m) m = v6;
            if (v7 < m) m = v7;
            if (v8 < m) m = v8;
            min9 = m;
        end
    endfunction

    
    
    function [7:0] lap1;
        input [7:0] c, up, dn, lf, rt;
        reg   [11:0] v;
        begin
            v = c * 5 + 12'd1024 - up - dn - lf - rt;
            if      (v > 12'd1279) lap1 = 8'hFF;   
            else if (v < 12'd1024) lap1 = 8'd0;    
            else                   lap1 = v[7:0];  
        end
    endfunction

    
    function [7:0] avg4;
        input [7:0] a, b, c, d;
        reg   [9:0] s;
        begin
            s    = a + b + c + d;
            avg4 = s[9:2];                         
        end
    endfunction

    function [7:0] lerp7;
        input [7:0] a, b;
        input [6:0] f;
        reg   [7:0] wl;                             
        reg   [15:0] s;
        begin
            wl    = 8'd128 - {1'b0, f};             
            s     = (wl * a) + ({1'b0, f} * b);     
            lerp7 = s[14:7];                        
        end
    endfunction

    wire [7:0] g_tl = gray_of(w_tl);
    wire [7:0] g_t  = gray_of(w_t);
    wire [7:0] g_tr = gray_of(w_tr);
    wire [7:0] g_l  = gray_of(w_l);
    wire [7:0] g_c  = gray_of(w_c);
    wire [7:0] g_r  = gray_of(w_r);
    wire [7:0] g_bl = gray_of(w_bl);
    wire [7:0] g_b  = gray_of(w_b);
    wire [7:0] g_br = gray_of(w_br);

    wire [7:0] g_max = max9(g_tl, g_t, g_tr, g_l, g_c, g_r, g_bl, g_b, g_br);
    wire [7:0] g_min = min9(g_tl, g_t, g_tr, g_l, g_c, g_r, g_bl, g_b, g_br);

    wire [7:0] r = w_c[23:16];
    wire [7:0] g = w_c[15:8];
    wire [7:0] b = w_c[7:0];

    localparam [7:0] THRESH = 8'd128;   

    
    wire is_red = (r > 8'd150) && (g < 8'd100) && (b < 8'd100) &&
                  (r > g + 60)  && (r > b + 60);

    wire [23:0] blk_avg = {avg4(w_c[23:16], w_r[23:16], w_b[23:16], w_br[23:16]),
                           avg4(w_c[15:8],  w_r[15:8],  w_b[15:8],  w_br[15:8]),
                           avg4(w_c[7:0],   w_r[7:0],   w_b[7:0],   w_br[7:0])};

    
    always @* begin
        hit = 1'b0;

        
        `ifdef ALGO_INVERT
            pix_out = ~w_c;                                   

        `elsif ALGO_GRAY
            pix_out = {g_c, g_c, g_c};                        

        `elsif ALGO_BINARIZE
            pix_out = (g_c > THRESH) ? 24'hFFFFFF : 24'h000000;  

        `elsif ALGO_RGB_SWAP
            pix_out = {b, g, r};                              

        `elsif ALGO_BRIGHT
            pix_out = {sat_add(r, 8'd60), sat_add(g, 8'd60), sat_add(b, 8'd60)};

        `elsif ALGO_RED_DETECT
            begin
                pix_out = is_red ? 24'hFFFFFF : {g_c, g_c, g_c};
                hit     = is_red;
            end

        
        `elsif ALGO_DILATE
            
            pix_out = {g_max, g_max, g_max};

        `elsif ALGO_ERODE
            
            pix_out = {g_min, g_min, g_min};

        `elsif ALGO_SHARPEN
            
            begin
                pix_out = { lap1(w_c[23:16], w_t[23:16], w_b[23:16], w_l[23:16], w_r[23:16]),
                            lap1(w_c[15:8],  w_t[15:8],  w_b[15:8],  w_l[15:8],  w_r[15:8]),
                            lap1(w_c[7:0],   w_t[7:0],   w_b[7:0],   w_l[7:0],   w_r[7:0]) };
            end

        `elsif ALGO_SCALE_UP2
            
            pix_out = w_c;

        `elsif ALGO_SCALE_DOWN2
            
            begin
                pix_out = blk_avg;
            end

        `elsif ALGO_SCALE_DOWN2_ALIAS
            
            pix_out = w_c;

        `elsif ALGO_TRAPEZOID
            
            begin
                pix_out = { lerp7(w_c[23:16], w_r[23:16], f),
                            lerp7(w_c[15:8],  w_r[15:8],  f),
                            lerp7(w_c[7:0],   w_r[7:0],   f) };
            end

        `else
            pix_out = w_c;                                    
        `endif
    end

endmodule
