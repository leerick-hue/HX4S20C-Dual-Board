# Run from this directory with td_commands_prompt.exe build.tcl.
set board_dir [file dirname [file normalize [info script]]]
set build_dir [file join $board_dir build]
file mkdir $build_dir
cd [file join $board_dir src td_project]
import_device eagle_s20.db -package EG4S20BG256
open_project -single_run [file join $board_dir src td_project HX4S20C_Extensions.al]
elaborate -top top
# Official TD AreaOptimizeHigh plus AdderChainThresholdHigh settings.
# Avoid exhausting MSlices with many short carry chains in the combined design.
set_param rtl min_ripple_len 18
set_param gate map_mode area_prior
set_param place effort high
set_param place seed 17
set_param route post_route_opt high
cd $build_dir
read_adc [file join $board_dir src user_source constraints_source pin.adc]
optimize_rtl
read_sdc [file join $board_dir src user_source constraints_source timing.sdc]
read_sdc -ip rfifo_32_32_512 [file join $board_dir src user_source hdl_source IP afifo_32_16_256.tcl]
read_sdc -ip wfifo_32_32_512 [file join $board_dir src user_source hdl_source IP afifo_16_32_256.tcl]
optimize_gate
read_adc [file join $board_dir src user_source constraints_source pll_locations.adc]
legalize_phy_inst
report_area -file HX4S20C_UNIFIED_gate.area
export_db HX4S20C_UNIFIED_gate.db
place
update_timing -mode manhattan
report_timing_summary -file HX4S20C_UNIFIED_place.timing
route
update_timing -mode final
report_area -io_info -file HX4S20C_UNIFIED_phy.area
report_timing_summary -file HX4S20C_UNIFIED_pr.timing
report_timing_status -file HX4S20C_UNIFIED_phy.ts
export_db HX4S20C_UNIFIED_pr.db
bitgen -bit HX4S20C_UNIFIED_TEST.bit
close_project
exit
