from pathlib import Path
import re, shutil
R=Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/album_hd_prefetch_20261029')
H=R/'src/user_source/hdl_source'
p=H/'SD/sd_card_bmp.v'
t=p.read_text(encoding='utf-8')
t=t.replace('parameter integer WIDTH             = 640,','parameter integer AUTO_SECONDS      = 5,\n    parameter integer WIDTH             = 640,')
t=t.replace('reg swap_pending,swap_accepted,write_done_seen,load_failed;', 'reg swap_pending,swap_accepted,write_done_seen,load_failed;\nreg prepared;\nlocalparam [31:0] AUTO_CYCLES = CLK_FREQ_HZ * AUTO_SECONDS;')
t=t.replace('assign remote_ready=scan_done && display_valid && !load_busy && !load_failed && !next_req_pending;', 'assign remote_ready=scan_done && display_valid && !next_req_pending && !swap_pending && !swap_accepted;')
t=t.replace('first_image_committed && !load_busy ? 4\'d6 :', 'first_image_committed && (!load_busy || prepared) ? 4\'d6 :')
t=t.replace("assign auto_tick  = (auto_cnt == (CLK_FREQ_HZ - 1));", "assign auto_tick  = (auto_cnt >= (AUTO_CYCLES - 1));")
start=t.index('always @(posedge clk or posedge rst) begin\n    if (rst) begin\n        wrfin_tgl_sync')
end=t.index('\nbmp_read_scaled #(',start)
t=t[:start]+'''// A completed back buffer is retained until NEXT or the slideshow deadline.
// Read/scale/write always targets the bank opposite the committed front bank.
always @(posedge clk or posedge rst) begin
    if (rst) begin
        wrfin_tgl_sync<=0; swap_pending<=0; swap_accepted<=0;
        write_done_seen<=0; source_done_seen<=0; prepared<=0; load_failed<=0;
        scan_start_pulse<=0; load_start_pulse<=0; load_sector<=0;
        scan_kicked<=0; first_image_committed<=0; auto_play_en<=0; auto_cnt<=0;
        img_found_count<=0; img_idx<=0; load_idx<=0; pending_buf_idx<=0;
        write_buf_idx<=0; disp_buf_idx<=0; next_req_pending<=0;
        load_busy<=0; display_valid<=0;
        img_sector0<=0;img_sector1<=0;img_sector2<=0;img_sector3<=0;
    end else begin
        wrfin_tgl_sync<={wrfin_tgl_sync[1:0],write_finish_toggle};
        scan_start_pulse<=0;load_start_pulse<=0;
        if(!sd_init_done) begin
            swap_pending<=0;swap_accepted<=0;prepared<=0;load_failed<=0;
            write_done_seen<=0;source_done_seen<=0;scan_kicked<=0;
            first_image_committed<=0;auto_play_en<=0;auto_cnt<=0;
            img_found_count<=0;img_idx<=0;load_idx<=0;pending_buf_idx<=0;
            write_buf_idx<=0;disp_buf_idx<=0;next_req_pending<=0;
            load_busy<=0;display_valid<=0;
        end else begin
            if(scan_found_valid)begin
                case(img_found_count)
                    0:img_sector0<=scan_found_sector;
                    1:img_sector1<=scan_found_sector;
                    2:img_sector2<=scan_found_sector;
                    3:img_sector3<=scan_found_sector;
                endcase
                if(img_found_count<4)img_found_count<=img_found_count+1'b1;
            end
            if(!scan_kicked && bmp_ready && media_ready)begin
                scan_start_pulse<=1;scan_kicked<=1;
            end
            // NEXT is held while a slow background load completes. A local
            // burst coalesces to one pending request; UART retains its queue.
            if(((key_next_press && !inhibit_sync[1]) || remote_next===1'b1)
                && scan_done && img_found_count>1)begin
                next_req_pending<=1;
                if(load_failed)load_failed<=0; // explicit retry of same target
            end
            if(key_auto_press && !inhibit_sync[1] && scan_done && img_found_count>1)begin
                auto_play_en<=!auto_play_en;auto_cnt<=0;
            end else if(remote_auto_valid===1'b1 && scan_done)begin
                auto_play_en<=remote_auto_enable;auto_cnt<=0;
            end else if(auto_play_en && display_valid && img_found_count>1)begin
                if(!auto_tick)auto_cnt<=auto_cnt+1'b1; // saturate while loading
            end else auto_cnt<=0;

            if(load_busy && parser_done)source_done_seen<=1;
            if(load_busy && write_finish_pulse)write_done_seen<=1;
            if(load_busy && source_done_seen && write_done_seen)prepared<=1;
            if(load_busy && parser_error)begin
                load_failed<=1;load_busy<=0;prepared<=0;
                swap_pending<=0;swap_accepted<=0;next_req_pending<=0;
            end
            // A pause arriving on the deadline wins over the automatic swap.
            if(prepared && !load_failed && !swap_pending &&
               (!first_image_committed || next_req_pending ||
                (auto_play_en && auto_tick && !key_auto_press && !remote_auto_valid)))begin
                swap_pending<=1;next_req_pending<=0;
            end
            if(swap_valid && swap_ready)swap_accepted<=1;
            if(swap_pending && swap_done)begin
                swap_pending<=0;swap_accepted<=0;prepared<=0;
                write_done_seen<=0;source_done_seen<=0;load_busy<=0;
                disp_buf_idx<=pending_buf_idx;img_idx<=load_idx;
                display_valid<=1;first_image_committed<=1;auto_cnt<=0;
            end

            // First image is loaded automatically; all later images are
            // proactively loaded, even with auto-play paused and no NEXT.
            if(scan_done && bmp_ready && !load_busy && !load_failed &&
                !swap_pending && img_found_count!=0 &&
                (!first_image_committed || img_found_count>1))begin
                load_idx<=first_image_committed ? next_from_current : 2'd0;
                load_sector<=sector_lut(first_image_committed ? next_from_current : 2'd0);
                pending_buf_idx<=next_buf_lut(disp_buf_idx,display_valid);
                write_buf_idx<=next_buf_lut(disp_buf_idx,display_valid);
                load_start_pulse<=1;load_busy<=1;
                source_done_seen<=0;write_done_seen<=0;prepared<=0;
            end
        end
    end
end
''' + t[end:]
t=t.replace('.KEEP_ASPECT(0)', '.KEEP_ASPECT(1)')
p.write_text(t,encoding='utf-8')
# Keep simulation copies identical to synthesis for every unencrypted module.
for p in H.rglob('*.v'):
    dest=R/'sim_source/rtl'/p.name
    if dest.exists():shutil.copy2(p,dest)
print('Implemented still-photo prefetch and aspect-fit')
