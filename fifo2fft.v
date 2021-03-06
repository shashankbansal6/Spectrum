// This module signals the audio2fifo module to begin filling the fifo.
//    (It stops signalling once it sees the fifo is filling -- via fifo "empty" goes low.)
// Once the fifo is full, this module pulls all of the data out at 10 MHz, feeding
//    it to the FFT module.
// This module then waits for fft to finish, and then moves the results into dual-port RAM for the 
//    NIOS processor to read it.
module fifo2fft
#( parameter FFT_POINTS, FFT_BUS )
(
   input reset,
   input clk,    // 10 MHz clock
   output reg start2fill,
   input adclrc,          // will use this to hold off read of fifo until L data starts.
   // FIFO interface
   input fifo_rdempty,
   input fifo_wrempty,
   input fifo_rdfull,
   input fifo_wrfull,
   output reg fifo_rdreq,
   // FFT interface
   input sink_ready,
   input source_valid,
   output reg sink_valid,
   output reg sink_sop,
   output reg sink_eop
);

localparam s0 = 0, s1 = 1, s2 = 2, s3 = 3, s4 = 4, s5 = 5, s6 = 6, s7 = 7;

reg [3:0] state;
reg reg_adclrc;
reg [FFT_BUS:0] wordcounter;

always @ (posedge clk ) reg_adclrc <= adclrc;

always @ (posedge clk or posedge reset) begin
   if( reset ) begin
      state <= s0;
      fifo_rdreq <= 0;
      start2fill <= 1'b0;
      sink_sop <= 1'b0;   // Tell the fft we haven't started sending it a packet yet.
      sink_eop <= 1'b0;
      sink_valid <= 1'b0;
      end
   else
      case( state )
         s0 : begin 
                 start2fill <= 1'b1;  // Tell audio input to fill the fifo with audio samples.
                 state <= s1;
              end
              
         s1 : begin
                 if( fifo_wrempty ) state <= s1;  // Stay here until fifo starts to fill, then
                 else begin 
                    start2fill = 1'b0;        // can stop telling audio path to start.
                    state <= s2;
                 end
              end
                 
         s2 : begin
                 if( (fifo_wrfull==1'b1) && (reg_adclrc==1'b1) ) state <= s3; // Wait here until fifo is full of audio data.
                 else state <= s2;                         // and L data is arriving from codec.
              end
              
         s3 : begin       // now dump the fifo into the fft.
                 if( ~sink_ready ) state <= s3;  // wait for fft to be ready to receive data.
                 else begin
                    // Output of fifo is connected to input of fft, so just tell fft to load the data.
                    fifo_rdreq <= 1'b1;
                    wordcounter <= 0;
                    state <= s4;
                    end
              end
              
         s4 : begin // continue to load fft. track # of words sent, in order to generate eop pulse.
                 wordcounter <= wordcounter + 1;
                 sink_valid <= 1'b1;
                 sink_sop <= 1'b1;
                 state <= s5;
              end
              
         s5 : begin
                 wordcounter <= wordcounter + 1;
                 sink_sop <= 1'b0;     // sop goes low after first byte has been loaded.
                 if( wordcounter == FFT_POINTS-1 ) begin
                    sink_eop = 1'b1;
                    state <= s6;
                    end
                 else state <= s5;   // stay here until time to put out eop pulse.
              end
              
         s6 : begin              // end the fifo loading into the fft.
                 sink_eop <= 0;
                 sink_valid <= 0;
                 fifo_rdreq <= 0;
                 if( source_valid == 1'b0 ) state <= s6;  // wait for fft results.
                 else state <= s7;
              end
              
         s7 : begin
                 // put output of fft into dual-port ram where the Nios can read it.
                 if( source_valid == 1 ) state <= s7;  // stay here until all results read.
                 else state <= s0;   // tell audio path to start filling the fifo again.
              end
              
         default : state <= s0;
         
      endcase
end
                 
endmodule
