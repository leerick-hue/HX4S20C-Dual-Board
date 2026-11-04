


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

// Keep the arithmetic grouped: this macro is used as a divisor by refresh.
// Must match sys_pll C1/C2 (50MHz); 2048 rows are refreshed within 64ms.
`define	  SDR_CLK_PERIOD				(1000000000/50000000)
`define   SELF_REFRESH_INTERVAL			(64000000/`SDR_CLK_PERIOD/(2**(`ROW_WIDTH)))

