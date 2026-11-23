// Waveform dump helper for dma_tb.v (not part of the submission)
// dma_tb.v has no $dumpfile, so this extra top-level module dumps it without modifying the TB.
module DMA_tb_dump ();
    initial begin
        $dumpfile("vcd/dma_tb.vcd");
        $dumpvars(0, DMA_tb);
    end
endmodule
