"""Isolated album/PCM/period/UART integration plus selected existing controls.

Does not regenerate the parent's bench, overwrite its logs, or access hardware.
The frozen production files and both original and new benches are copied into
one candidate-owned stage before independent ModelSim jobs run in parallel.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import argparse
import hashlib
import json
import shutil
import struct
import subprocess
import time
import uuid

R = Path(__file__).resolve().parents[1]
H = R / 'src/user_source/hdl_source'
E = H / 'extensions'
OLD = Path('E:/HX4S20C_Extensions/hx4s20c_media_core/board/media_hd_unified_20261025')
BIN = Path('E:/Modelsim/modelsim_ase/win32aloem')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--jobs', nargs='+', choices=['album', 'ui', 'infrared'],
                        default=['album', 'ui', 'infrared'])
    parser.add_argument('--timeout', type=int, default=1800)
    args = parser.parse_args()
    tag = time.strftime('%Y%m%d_%H%M%S') + '_' + uuid.uuid4().hex[:6]
    stage = R / 'sim_stages' / ('period_integration_' + tag)
    out = R / 'sim_logs' / ('period_integration_' + tag)
    stage.mkdir(parents=True)
    out.mkdir(parents=True)
    common = ['ir_keymap.v', 'us_tick_1m.v', 'ir_nec_rx.v',
              'ir_media_bridge.v', 'media_command_cdc.v', 'key_debounce.v']
    album_files = [R / 'rtl' / n for n in [
        'media_catalog.v', 'media_mode_reset.v', 'unified_media_source.v',
        'sd_sector_cdc.v', 'hxjv_pcm_player.v']]
    album_files += [H / n for n in [
        'SD/sd_card_bmp.v', 'SD/bmp_read_scaled.v',
        'SD/frame_fifo_write.v', 'pixel_write_fifo.v']]
    album_files += [E / n for n in [
        'bmp24_scale_stream.v', 'sd_sector_arbiter.v', 'audio_pcm_fifo.v',
        'rgb565_pack.v', 'reset_sync.v', 'frame_swap_fx_cdc.v',
        'board_remote_control.v', 'event_packet_rx.v', 'uart_rx.v',
        'event_fifo.v', 'ir_keymap.v', 'us_tick_1m.v', 'ir_nec_rx.v',
        'ir_media_bridge.v', 'media_command_cdc.v']]
    ui_files = [E / n for n in common + [
        'media_control_arbiter.v', 'board_remote_control.v',
        'event_packet_rx.v', 'uart_rx.v', 'event_fifo.v']]
    ui_files += [H / 'board_video_controls.v', R / 'rtl/media_mode_reset.v']
    ir_files = [E / n for n in common] + [H / 'board_video_controls.v']
    jobs = {
        'album': (album_files, R / 'sim/tb_period_integration.sv', 'tb_period_integration'),
        'ui': (ui_files, R / 'sim/tb_unified_controls.sv', 'tb_unified_controls'),
        'infrared': (ir_files, R / 'sim/tb_phone_ir_media.sv', 'tb_phone_ir_media'),
    }
    selected = list(dict.fromkeys(args.jobs))
    inputs = {Path(__file__).resolve()}
    for name in selected:
        files, bench, _ = jobs[name]
        inputs.update(files + [bench])
    fixture_inputs = []
    fixture = stage / 'fixtures'
    if 'album' in selected:
        fixture.mkdir()
        image_path = OLD / 'sim/fixtures/combined.img'
        image = image_path.read_bytes()
        fixture_inputs.append(image_path)
        (fixture / 'combined.hex').write_text(''.join(f'{b:02x}\n' for b in image))
        for name in ['pcm_album.hex', 'video0.hex', 'video1.hex', 'video2.hex', 'pcm_video.hex']:
            path = OLD / 'sim/fixtures' / name
            fixture_inputs.append(path)
            shutil.copy2(path, fixture / name)
        for index in range(2):
            path = OLD / f'sim/fixtures/photo{index}.bmp'
            fixture_inputs.append(path)
            bmp = path.read_bytes()
            offset = struct.unpack_from('<I', bmp, 10)[0]
            width, raw_height = struct.unpack_from('<ii', bmp, 18)
            height = abs(raw_height)
            stride = (width * 3 + 3) & ~3
            fit_width, fit_height = 1280, 720
            if width * 720 > height * 1280:
                fit_height = max(1, height * 1280 // width)
            elif width * 720 < height * 1280:
                fit_width = max(1, width * 720 // height)
            ox, oy = (1280 - fit_width) // 2, (720 - fit_height) // 2

            def pixel(x, y):
                if not (ox <= x < ox + fit_width and oy <= y < oy + fit_height):
                    return 0
                sx, sy = (x - ox) * width // fit_width, (y - oy) * height // fit_height
                if raw_height > 0:
                    sy = height - 1 - sy
                b, g, red = bmp[offset + sy * stride + sx * 3:offset + sy * stride + sx * 3 + 3]
                return ((red >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)

            with (fixture / f'photo{index}.hex').open('w') as stream:
                for y in range(720):
                    for x in range(0, 1280, 2):
                        stream.write(f'{pixel(x, y) | (pixel(x + 1, y) << 16):08x}\n')
    inputs.update(fixture_inputs)
    hashes = {str(p): sha(p) for p in sorted(inputs)}
    staged = {}
    for path in inputs:
        if not path.is_relative_to(R):
            continue
        dest = stage / path.relative_to(R)
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        staged[str(dest)] = sha(dest)
    fixture_hashes = {str(p): sha(p) for p in fixture.glob('*') if p.is_file()}
    manifest = dict(pass_=False, stage=str(stage), out=str(out), jobs=selected,
                    sources=hashes, staged_sources=staged, fixtures=fixture_hashes,
                    fixture_origin=str(OLD), results={},
                    scope='Native 1280x720 fit BMP -> actual RGB565 pack/write FIFO/write DMA/swap/fade, '
                          'concurrent shared-sector PCM, local next and long-period key, actual115200 UART '
                          'receiver/legacy IR bridge auto pause/resume; existing UI/physical NEC regressions. '
                          'Actual40/50/74.25/100MHz clocks; auto/debounce/hold constants1000x accelerated, '
                          'vblank/fade accelerated, synthetic SD bytes and memory app acceptance. '
                          'No physical SD init, SDRAM chip/read PHY, HDMI electrical or hardware claim.')
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    print('OUT', out, 'STAGE', stage, flush=True)
    started = time.monotonic()

    def run_job(name):
        files, bench, target = jobs[name]
        cwd = stage / 'jobs' / name
        logs = out / name
        cwd.mkdir(parents=True)
        logs.mkdir()
        sources = [stage / p.relative_to(R) for p in files + [bench]]
        plusargs = []
        if name == 'album':
            plusargs = ['+IMAGE=' + str(fixture / 'combined.hex'),
                        '+BYTES=' + str(len(image)), '+FIXTURE=' + str(fixture)]
        commands = [
            ['vlib.exe', 'work'],
            ['vlog.exe', '-sv', *map(str, sources)],
            ['vsim.exe', '-c', '-t', '1ps', '-onfinish', 'stop', 'work.' + target,
             *plusargs, '-do', 'onerror {quit -code 1}; run -all; quit -code 0'],
        ]
        rec = {'pass': False, 'stage': str(cwd), 'sources': {str(p): sha(p) for p in files + [bench]},
               'commands': commands}
        job_start = time.monotonic()
        try:
            for index, command in enumerate(commands):
                print(name, 'step', index, command[0], flush=True)
                with (logs / f'{index}.log').open('w') as log:
                    proc = subprocess.run([str(BIN / command[0]), *command[1:]], cwd=cwd,
                                          stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
                text = (logs / f'{index}.log').read_text(errors='replace')
                assert not proc.returncode and '** Error:' not in text and '** Fatal:' not in text, text[-7000:]
            rec['markers'] = [line for line in text.splitlines() if any(word in line for word in
                              ['PASS ', 'METRIC ', 'PERIOD_KEYS_PASS', 'REMOTE_PAUSE_PASS'])]
            expected = {'album': 'PASS period_integration:', 'ui': 'PASS photo_ui ',
                        'infrared': 'PASS phone physical NEC:'}[name]
            assert expected in text, text[-5000:]
            if name == 'album':
                rec['frames'] = []
                for index, asset in enumerate([0, 1, 0, 1]):
                    frame = cwd / f'frame_{index}.hex'
                    golden = fixture / f'photo{asset}.hex'
                    assert frame.read_text().lower() == golden.read_text().lower(), f'frame {index}'
                    rec['frames'].append(dict(commit=index, asset=asset, words=460800,
                                              sha256=sha(frame), reference_sha256=sha(golden)))
            assert all(sha(p) == rec['sources'][str(p)] for p in files + [bench])
            rec['pass'] = True
            print('\n'.join(rec['markers']), flush=True)
        except Exception as error:
            rec['error'] = str(error)
            print(name, 'FAIL', str(error)[-7000:], flush=True)
        rec['wall_seconds'] = time.monotonic() - job_start
        (logs / 'summary.json').write_text(json.dumps(rec, indent=2))
        return rec

    with ThreadPoolExecutor(max_workers=len(selected)) as workers:
        futures = {workers.submit(run_job, name): name for name in selected}
        for future in as_completed(futures):
            name = futures[future]
            try:
                manifest['results'][name] = future.result()
            except Exception as error:
                manifest['results'][name] = {'pass': False, 'error': str(error)}
    manifest['pass'] = all(v['pass'] for v in manifest['results'].values())
    manifest['sources_unchanged'] = all(sha(Path(p)) == digest for p, digest in hashes.items())
    manifest['staged_sources_unchanged'] = all(sha(Path(p)) == digest for p, digest in staged.items())
    manifest['fixtures_unchanged'] = all(sha(Path(p)) == digest for p, digest in fixture_hashes.items())
    manifest['pass'] = manifest['pass'] and manifest['sources_unchanged'] and manifest['staged_sources_unchanged'] and manifest['fixtures_unchanged']
    manifest.pop('pass_', None)
    manifest['wall_seconds'] = time.monotonic() - started
    (out / 'summary.json').write_text(json.dumps(manifest, indent=2))
    print('PASS period suite' if manifest['pass'] else 'FAIL period suite', out, flush=True)
    return 0 if manifest['pass'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
