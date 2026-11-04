`timescale 1ns/1ps

// Actual UI, keyboard UART/packet/queue, arbiters and both command mailboxes.
// Only the unchanged NEC decoder/keymap boundary is injected, not its waveform.
module tb_unified_controls;
    reg video_clk=0, sd_clk=0;
    always #6.734007 video_clk=~video_clk;
    always #12.5 sd_clk=~sd_clk;
    reg rst_n=0, vblank=0;
    reg [2:0] key_n=3'b111;
    reg active_video=0, consume_enable=1, album_ready=1;
    wire media_rst;
    wire media_rst_n=rst_n && !media_rst;
    wire [3:0] brightness,contrast,volume_level;
    wire [2:0] edit_mode;
    wire bars_enable,music_play,want_video,control_valid,control_ready;
    wire [7:0] control_id;
    wire uart_valid,uart_ready;
    wire [3:0] uart_code;
    wire ir_valid,ir_ready;
    wire [7:0] ir_id;
    reg link_rx=1;
    wire remote_next,remote_auto_valid,remote_auto_enable,legacy_ready;
    wire photo_next,photo_auto_valid,photo_auto_enable;
    wire [31:0] accepted,duplicates,unsupported,packet_errors;
    reg album_auto=1;
    wire auto_enabled=active_video?music_play:album_auto;
    reg inject_valid=0;
    reg [7:0] inject_id=0;
    integer checks=0,control_count=0,photo_next_count=0,photo_auto_count=0;
    integer codes_seen[0:255];
    integer cycles=0;
    reg [7:0] sequence_number=0;

    board_video_controls #(.KEY_CYCLES(3)) controls(
        .clk(video_clk),.rst_n(rst_n),.vblank_start(vblank),.key_n(key_n),
        .command_valid(control_valid && consume_enable),.command_id(control_id),.command_ready(control_ready),
        .brightness(brightness),.contrast(contrast),.edit_mode(edit_mode),.volume_level(volume_level),
        .bars_enable(bars_enable),.music_play(music_play));
    assign want_video=1'b0;
    media_mode_reset #(.HOLD_CYCLES(8)) restart(
        .clk(video_clk),.rst(!rst_n),.want_video(want_video),.media_rst(media_rst));
    media_control_arbiter commands(
        .sd_clk(sd_clk),.sd_rst_n(media_rst_n),.video_mode(active_video),
        .uart_valid(uart_valid),.uart_ready(uart_ready),.uart_code(uart_code),
        .video_clk(video_clk),.video_rst_n(media_rst_n),.ir_valid(ir_valid),.ir_ready(ir_ready),.ir_id(ir_id),
        .control_valid(control_valid),.control_ready(control_ready && consume_enable),.control_id(control_id));
    ir_media_bridge #(.VIDEO_CLK_HZ(74250000)) infrared(
        .video_clk(video_clk),.video_rst_n(media_rst_n),.sd_clk(sd_clk),.sd_rst_n(media_rst_n),.ir_in(1'b1),
        .video_mode(active_video),.album_ready(album_ready),.auto_enabled(auto_enabled),
        .legacy_next(remote_next),.legacy_auto_valid(remote_auto_valid),.legacy_auto_enable(remote_auto_enable),
        .legacy_ready(legacy_ready),.photo_next(photo_next),.photo_auto_valid(photo_auto_valid),.photo_auto_enable(photo_auto_enable),
        .control_valid(ir_valid),.control_ready(ir_ready),.control_id(ir_id),
        .last_code(),.error_count(),.dropped_count(),.seen());
    // Ten 40-MHz clocks per bit accelerate the same actual UART state machine.
    board_remote_control #(.CLK_HZ(40000000),.BAUD(4000000),.ACK_ENABLE(1)) remote(
        .clk(sd_clk),.rst_n(media_rst_n),.link_rx(link_rx),.album_ready(legacy_ready),
        .control_ready(uart_ready),.control_valid(uart_valid),.control_code(uart_code),
        .next_pulse(remote_next),.auto_valid(remote_auto_valid),.auto_enable(remote_auto_enable),
        .accepted_count(accepted),.duplicate_count(duplicates),.unsupported_count(unsupported),.packet_error_count(packet_errors),.ack_ready(1'b1));

    always @(posedge video_clk) begin
        cycles=cycles+1;
        if(cycles>200000) $fatal(1,"controls timeout");
        if(rst_n && control_valid && control_ready && consume_enable) begin
            control_count=control_count+1;
            codes_seen[control_id]=codes_seen[control_id]+1;
        end
    end
    always @(posedge sd_clk) begin
        if(rst_n && !media_rst) begin
            if(photo_next) photo_next_count=photo_next_count+1;
            if(photo_auto_valid) begin
                photo_auto_count=photo_auto_count+1;
                album_auto<=photo_auto_enable;
            end
        end
    end

    task automatic check(input bit ok,input string message);
        begin
            checks=checks+1;
            if(!ok) $fatal(1,"check %0d: %s (mode=%0d B=%0d C=%0d V=%0d bars=%0b play=%0b source=%0b)",
                checks,message,edit_mode,brightness,contrast,volume_level,bars_enable,music_play,want_video);
        end
    endtask
    task automatic settle;
        begin repeat(24) @(negedge video_clk); end
    endtask
    task automatic commit;
        begin
            @(negedge video_clk);vblank=1;
            @(negedge video_clk);vblank=0;
        end
    endtask
    task automatic press(input integer index);
        begin
            @(negedge video_clk);key_n[index]=0;
            repeat(12) @(negedge video_clk);
            key_n[index]=1;
            repeat(12) @(negedge video_clk);
        end
    endtask
    task automatic mode_step(input integer expected);
        begin press(2);check(edit_mode==expected,"physical mode cycle");end
    endtask
    task automatic wait_restart;
        begin
            wait(!media_rst);
            settle();
            active_video=want_video;
            settle();
        end
    endtask
    task automatic inject_ir(input [7:0] id);
        integer guard;
        begin
            @(negedge video_clk);inject_id=id;inject_valid=1;
            guard=0;
            @(posedge video_clk);
            while(!infrared.cmd_ready) begin
                guard=guard+1;
                if(guard>100) $fatal(1,"IR command handshake blocked id=%0d",id);
                @(posedge video_clk);
            end
            @(negedge video_clk);inject_valid=0;
            settle();
        end
    endtask
    function automatic [7:0] crc_byte(input [7:0] prior,input [7:0] data);
        reg [7:0] c;
        begin
            c=prior^data;
            for(integer j=0;j<8;j=j+1)c=c[7]?(c<<1)^8'h07:c<<1;
            crc_byte=c;
        end
    endfunction
    task automatic send_byte(input [7:0] data);
        begin
            @(negedge sd_clk);link_rx=0;
            repeat(10)@(negedge sd_clk);
            for(integer j=0;j<8;j=j+1)begin
                link_rx=data[j];repeat(10)@(negedge sd_clk);
            end
            link_rx=1;repeat(12)@(negedge sd_clk);
        end
    endtask
    task automatic keyboard(input [3:0] code);
        reg [7:0] crc;
        begin
            crc=0;
            crc=crc_byte(crc,1);crc=crc_byte(crc,1);crc=crc_byte(crc,1);
            crc=crc_byte(crc,sequence_number);crc=crc_byte(crc,{4'b0,code});crc=crc_byte(crc,0);
            send_byte(8'ha5);send_byte(8'h5a);send_byte(1);send_byte(1);send_byte(1);
            send_byte(sequence_number);send_byte({4'b0,code});send_byte(0);send_byte(crc);
            sequence_number=sequence_number+1'b1;
            settle();
        end
    endtask

    integer n,before_count,before_photo,before_next;
    initial begin
        for(n=0;n<256;n=n+1)codes_seen[n]=0;
        force infrared.cmd=inject_id;
        force infrared.cmd_valid=inject_valid;
        repeat(4)@(negedge video_clk);rst_n=1;
        wait_restart();
        check(edit_mode==0 && brightness==4 && contrast==4 && volume_level==8 &&
              bars_enable && music_play && !want_video,"UI defaults");

        // A short pulse is rejected; one held mode button generates one event.
        @(negedge video_clk);key_n[2]=0;
        @(negedge video_clk);key_n[2]=1;settle();
        check(edit_mode==0,"debounce rejects short pulse");
        @(negedge video_clk);key_n[2]=0;
        repeat(40)@(negedge video_clk);
        check(edit_mode==1,"held key advances once");
        key_n[2]=1;settle();
        for(n=2;n<=5;n=n+1)mode_step(n);
        mode_step(0);

        mode_step(1);press(0);
        check(brightness==4,"brightness remains pending before vblank");commit();check(brightness==5,"physical brightness up");
        press(1);commit();check(brightness==4,"physical brightness down");
        mode_step(2);press(0);commit();check(contrast==5,"physical contrast up");
        press(1);commit();check(contrast==4,"physical contrast down");
        mode_step(3);press(1);commit();check(volume_level==7,"physical volume down");
        press(0);commit();check(volume_level==8,"physical volume up");
        mode_step(4);press(1);check(bars_enable,"bars change waits for vblank");commit();check(!bars_enable,"physical bars off");
        press(0);commit();check(bars_enable,"physical bars on");
        mode_step(5);press(1);check(!music_play,"physical pause");press(0);check(music_play,"physical resume");
        mode_step(0);

        before_count=codes_seen[13];before_photo=photo_auto_count;
        keyboard(1);check(edit_mode==0 && music_play && !album_auto && codes_seen[13]==before_count+1 && photo_auto_count==before_photo+1,
            "album keyboard pause keeps legacy auto-off and maps to album UI");
        keyboard(2);check(album_auto && music_play && codes_seen[13]==before_count+2 && photo_auto_count==before_photo+2,
            "album keyboard resume keeps legacy auto-on and maps to album UI");
        keyboard(10);check(brightness==4,"keyboard brightness pending");commit();check(brightness==5 && edit_mode==1,"keyboard brightness up");
        keyboard(8);commit();check(brightness==4,"keyboard brightness down");keyboard(11);check(edit_mode==1,"keyboard brightness edit shortcut");
        keyboard(14);commit();check(contrast==5 && edit_mode==2,"keyboard contrast up");
        keyboard(12);commit();check(contrast==4,"keyboard contrast down");keyboard(15);check(edit_mode==2,"keyboard contrast edit shortcut");
        keyboard(10);keyboard(14);commit();check(brightness==5 && contrast==5,"adjust both before neutral");
        keyboard(9);commit();check(brightness==4 && contrast==4,"keyboard neutral resets brightness and contrast");
        keyboard(4);commit();check(volume_level==7 && edit_mode==3,"keyboard volume down");
        keyboard(6);commit();check(volume_level==8,"keyboard volume up");
        keyboard(5);commit();check(volume_level==0,"keyboard mute");keyboard(5);commit();check(volume_level==8,"keyboard restores previous volume");
        keyboard(7);check(edit_mode==3,"keyboard volume edit shortcut");
        keyboard(13);commit();check(!bars_enable && edit_mode==4,"keyboard bars toggle off");
        keyboard(13);commit();check(bars_enable,"keyboard bars toggle on");
        keyboard(3);check(edit_mode==0,"keyboard album edit shortcut");
        before_next=photo_next_count;keyboard(0);check(edit_mode==0 && photo_next_count==before_next+1,"keyboard next reaches photo output once");

        before_count=control_count;before_photo=photo_auto_count;
        inject_ir(2);check(!album_auto && photo_auto_count==before_photo+1 && control_count==before_count,"album IR auto off uses photo mailbox");
        inject_ir(3);check(album_auto && photo_auto_count==before_photo+2 && control_count==before_count,"album IR auto on uses photo mailbox");
        inject_ir(20);check(!album_auto,"album IR auto toggle off");inject_ir(20);check(album_auto,"album IR auto toggle on");
        before_next=photo_next_count;inject_ir(1);check(photo_next_count==before_next+1,"IR next uses photo mailbox once");

        for(n=7;n>=0;n=n-1)begin inject_ir(6);commit();check(volume_level==n,"volume all levels down to zero");end
        inject_ir(6);commit();check(volume_level==0,"volume lower saturation");
        for(n=1;n<=8;n=n+1)begin inject_ir(4);commit();check(volume_level==n,"volume all levels up to eight");end
        inject_ir(4);commit();check(volume_level==8,"volume upper saturation");
        inject_ir(17);check(!music_play && edit_mode==5,"legacy pause shortcut");
        inject_ir(18);check(music_play,"legacy resume shortcut");inject_ir(19);check(!music_play,"legacy toggle pauses");
        inject_ir(19);check(music_play,"legacy toggle resumes");

        check(packet_errors==0 && duplicates==0 && unsupported==0,"UART error counters");
        $display("PASS photo_ui checks=%0d controls=%0d next=%0d auto=%0d: six physical-key modes/debounce, vblank commits, all16 UART shortcuts through queue/arbiter/CDC, IR command mailbox, saturation/mute/music",checks,control_count,photo_next_count,photo_auto_count);
        $display("SCOPE accelerated UART10clocks/bit and debounce3clocks, IR command boundary injected; actual74.25/40MHz clocks; physical NEC/115200 ACK covered separately");
        $finish;
    end
endmodule
