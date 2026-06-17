// =============================================================================
// uart_regs.sv — Memory-mapped register file for UART controller
// =============================================================================
//
// Address map (2-bit):
//   2'h0  CTRL_REG   RW  [3:0] tx_en|rx_en|parity_en|parity_type; [7:4] reserved=0
//   2'h1  STATUS_REG RO  [3:0] tx_busy|rx_valid|rx_error|rx_parity_err; [7:4] reserved=0
//   2'h2  BAUD_REG   RW  [7:0] baud divisor (software visible; RTL uses compile-time params)
//   2'h3  (unused)       reads as 8'h00, writes ignored
//
// Read path:  always_comb mux → registered into reg_rdata on posedge clk
//             reg_rdata returns to 8'h00 one cycle after reg_ren deasserts
// Write path: always_ff; STATUS_REG writes silently ignored; reserved bits not stored
// =============================================================================
module uart_regs (
    input  logic        clk,
    input  logic        rst_n,
    // Register bus
    input  logic [1:0]  reg_addr,
    input  logic [7:0]  reg_wdata,
    input  logic        reg_wen,
    input  logic        reg_ren,
    output logic [7:0]  reg_rdata,
    // Status inputs — wired directly into STATUS_REG read data
    input  logic        tx_busy,
    input  logic        rx_valid,
    input  logic        rx_error,
    input  logic        rx_parity_err,
    // Control/baud outputs — driven combinationally from stored registers
    output logic        tx_en,
    output logic        rx_en,
    output logic        parity_en,
    output logic        parity_type,
    output logic [7:0]  baud_div
);

    // -----------------------------------------------------------------------
    // Address constants
    // -----------------------------------------------------------------------
    typedef enum logic [1:0] {
        CTRL_ADDR   = 2'h0,
        STATUS_ADDR = 2'h1,
        BAUD_ADDR   = 2'h2
    } reg_addr_t;

    // -----------------------------------------------------------------------
    // Internal register storage
    // Only the writable, non-reserved bits are stored.
    // -----------------------------------------------------------------------
    logic [3:0] ctrl_reg;  // [0]=tx_en [1]=rx_en [2]=parity_en [3]=parity_type
    logic [7:0] baud_reg;

    // -----------------------------------------------------------------------
    // Write logic
    // STATUS_REG address falls into the default arm — silently discarded.
    // Reserved bits in CTRL_REG ([7:4]) are never stored.
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl_reg <= 4'h0;
            baud_reg <= 8'h00;
        end else if (reg_wen) begin
            case (reg_addr)
                CTRL_ADDR: ctrl_reg <= reg_wdata[3:0];
                BAUD_ADDR: baud_reg <= reg_wdata;
                default:   ;  // STATUS_ADDR and 2'h3 writes silently ignored
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // Read mux — purely combinational
    // STATUS_REG is assembled directly from live input ports (no storage).
    // Default arm covers the unused 2'h3 address.
    // -----------------------------------------------------------------------
    logic [7:0] rdata_mux;

    always_comb begin
        rdata_mux = 8'h00;
        case (reg_addr)
            CTRL_ADDR:   rdata_mux = {4'h0, ctrl_reg};
            STATUS_ADDR: rdata_mux = {4'h0, rx_parity_err, rx_error, rx_valid, tx_busy};
            BAUD_ADDR:   rdata_mux = baud_reg;
            default:     rdata_mux = 8'h00;
        endcase
    end

    // -----------------------------------------------------------------------
    // Registered read data
    // Captured from the combinational mux on the cycle reg_ren is asserted.
    // Returns to 8'h00 the cycle after reg_ren deasserts (no hold-last-value).
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_rdata <= 8'h00;
        end else begin
            reg_rdata <= reg_ren ? rdata_mux : 8'h00;
        end
    end

    // -----------------------------------------------------------------------
    // Control/baud outputs — combinational wires from stored register bits
    // -----------------------------------------------------------------------
    always_comb begin
        tx_en       = ctrl_reg[0];
        rx_en       = ctrl_reg[1];
        parity_en   = ctrl_reg[2];
        parity_type = ctrl_reg[3];
        baud_div    = baud_reg;
    end

endmodule
