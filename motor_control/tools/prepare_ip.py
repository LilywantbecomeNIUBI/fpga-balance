"""Configure the installed vendor FOC Light template; never decrypt or replace it."""
from pathlib import Path
import hashlib
import json
import shutil
import os

ROOT = Path(__file__).resolve().parents[1]
IDE = Path(os.environ.get('GOWIN_IDE', r'C:\Gowin\Gowin_V1.9.12.04_x64\IDE'))

def main():
    source = IDE / 'ipcore/FCLCL/data'
    target = ROOT / 'ip/foc_light'
    target.mkdir(parents=True, exist_ok=True)
    provenance = []
    for name in ['foc_current_loop_control_light_wrap.v',
                 'foc_current_loop_control_light_encrypt.v', 'static_macro_define.v']:
        shutil.copyfile(source / name, target / name)
        provenance.append({'source': str(source / name), 'file': name,
                           'sha256': hashlib.sha256((target / name).read_bytes()).hexdigest()})
    (target / 'define.vh').write_text(
        '`define DEFINE_VH\n`define MODULE_NAME motor_gowin_foc_light\n'
        '`define foc_clarke_transform_2i\n`define gw5a_device\n`define DEBUG_MODE\n', encoding='ascii')
    # 50 MHz / (2 * 1250) = 20 kHz; 50 cycles = 1 us deadtime.
    (target / 'parameter.vh').write_text(
        '`define PARAMETER_VH\nparameter PWM_HALF_PERIOD = 1250;\nparameter PWM_DEADTIME = 50;\n'
        "parameter PWM_INVERSE = 1'b0;\n", encoding='ascii')
    (target / 'SOURCE.json').write_text(json.dumps(provenance, indent=2), encoding='utf-8')
    project = ROOT / 'build/ip_probe'
    project.mkdir(parents=True, exist_ok=True)
    files = ''.join('<File path="' + (target / name).as_posix() + '" type="file.verilog" enable="1"/>'
                    for name in ['foc_current_loop_control_light_wrap.v', 'foc_current_loop_control_light_encrypt.v'])
    (project / 'ip_probe.gprj').write_text(
        '<Project><Template>FPGA</Template><Version>5</Version>'
        '<Device name="GW5AT-138B" pn="GW5AT-LV138PG484AC1/I0">gw5at138b-012</Device>'
        '<FileList>' + files + '</FileList></Project>', encoding='utf-8')
    (project / 'syn.tcl').write_text(
        'open_project {' + (project / 'ip_probe.gprj').as_posix() + '}\n'
        'set_option -top_module motor_gowin_foc_light\n'
        'set_option -verilog_std sysv2017\nset_option -output_base_name motor_foc\n'
        'run syn\n', encoding='utf-8')
    print(project / 'syn.tcl')

if __name__ == '__main__':
    main()
