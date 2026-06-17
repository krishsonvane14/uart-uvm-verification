// =============================================================================
// uart_tx.sv — UART Transmitter
// =============================================================================
module uart_tx #(
    parameter int CLK_FREQ    = 50_000_000,  // Hz
    parameter int BAUD_RATE   = 9_600,       // bps
    parameter int DATA_BITS   = 8,
    parameter bit PARITY_EN   = 1'b1,
    parameter bit PARITY_TYPE = 1'b0         // 0=even, 1=odd
)(
    input  logic                 clk,
    input  logic                 rst_n,
    // Data interface
    input  logic [DATA_BITS-1:0] tx_data,
    input  logic                 tx_valid,
    output logic                 tx_ready,
    // Serial output
    output logic                 tx_serial,
    output logic                 tx_busy
);

    // -----------------------------------------------------------------------
    // Baud divider — how many clock cycles per bit period
    // -----------------------------------------------------------------------
    localparam int BAUD_DIV = CLK_FREQ / BAUD_RATE;

    // -----------------------------------------------------------------------
    // State encoding
    // -----------------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE   = 3'b000,
        START  = 3'b001,
        DATA   = 3'b010,
        PARITY = 3'b011,
        STOP   = 3'b100
    } state_t;

    state_t state;

    // -----------------------------------------------------------------------
    // Internal signals
    // -----------------------------------------------------------------------
    logic [$clog2(BAUD_DIV)-1:0] baud_cnt;
    logic                         baud_tick;
    logic [DATA_BITS-1:0]         shift_reg;
    logic [DATA_BITS-1:0]         tx_data_latch;  // original data saved for parity
    logic [$clog2(DATA_BITS):0]   bit_cnt;
    logic                         parity_bit;

    // -----------------------------------------------------------------------
    // Parity — combinational, computed from latched original data
    // Seed with PARITY_TYPE: 0 for even, 1 for odd
    // -----------------------------------------------------------------------
    always_comb begin
        parity_bit = PARITY_TYPE;
        for (int i = 0; i < DATA_BITS; i++) begin
            parity_bit = parity_bit ^ tx_data_latch[i];
        end
    end

    // -----------------------------------------------------------------------
    // Baud tick generator
    // Holds at 0 during IDLE, counts and pulses every BAUD_DIV cycles otherwise
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b0;
        end else if (state == IDLE) begin
            baud_cnt  <= '0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_cnt == BAUD_DIV - 1) begin
                baud_cnt  <= '0;
                baud_tick <= 1'b1;
            end else begin
                baud_cnt  <= baud_cnt + 1;
                baud_tick <= 1'b0;
            end
        end
    end

    // -----------------------------------------------------------------------
    // Main state machine
    // -----------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            tx_serial     <= 1'b1;   // UART idles high
            tx_busy       <= 1'b0;
            tx_ready      <= 1'b1;
            shift_reg     <= '0;
            tx_data_latch <= '0;
            bit_cnt       <= '0;
        end else begin
            case (state)

                // -------------------------------------------------------------
                // IDLE: line held high, waiting for tx_valid
                // -------------------------------------------------------------
                IDLE: begin
                    tx_serial <= 1'b1;
                    tx_busy   <= 1'b0;
                    tx_ready  <= 1'b1;
                    if (tx_valid) begin
                        shift_reg     <= tx_data;
                        tx_data_latch <= tx_data;  // save for parity — shift_reg gets destroyed
                        bit_cnt       <= '0;
                        tx_busy       <= 1'b1;
                        tx_ready      <= 1'b0;
                        state         <= START;
                    end
                end

                // -------------------------------------------------------------
                // START: drive logic 0 for one full baud period
                // -------------------------------------------------------------
                START: begin
                    tx_serial <= 1'b0;
                    if (baud_tick) state <= DATA;
                end

                // -------------------------------------------------------------
                // DATA: shift out DATA_BITS bits, LSB first
                // -------------------------------------------------------------
                DATA: begin
                    tx_serial <= shift_reg[0];
                    if (baud_tick) begin
                        shift_reg <= {'0, shift_reg[DATA_BITS-1:1]};  // logical right shift
                        if (bit_cnt == DATA_BITS - 1) begin
                            bit_cnt <= '0;
                            state   <= PARITY_EN ? PARITY : STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1;
                        end
                    end
                end

                // -------------------------------------------------------------
                // PARITY: drive computed parity bit for one baud period
                // -------------------------------------------------------------
                PARITY: begin
                    tx_serial <= parity_bit;
                    if (baud_tick) state <= STOP;
                end

                // -------------------------------------------------------------
                // STOP: drive logic 1 for one full baud period, then return idle
                // -------------------------------------------------------------
                STOP: begin
                    tx_serial <= 1'b1;
                    if (baud_tick) begin
                        state    <= IDLE;
                        tx_busy  <= 1'b0;
                        tx_ready <= 1'b1;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule
