"""RISCOF reference plugin: Spike and, when present, the Sail model.

`primary` in config.ini picks whose signature RISCOF compares against. The other
model still runs, its signature lands beside the primary as <model>.signature,
and sim/report.py checks the two agree, so a reference bug cannot pass unnoticed.

Spike reserves [0x0,0x2000), so it gets one region from 0x8000 sized for the
largest arch test. --pc enters at the ELF entry because --disable-dtb leaves no
boot ROM.
"""
import json
import logging
import os
import shlex

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


def march_for(isa):
    m = isa.lower()
    for ext in ('zicsr', 'zifencei'):
        if ext not in m:
            m += '_' + ext
    return m


class refmodel(pluginTemplate):
    __model__ = 'refmodel'
    __version__ = 'spike-3d8eb08+sail'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get('config')
        self.num_jobs = str(config.get('jobs', 8))
        self.pluginpath = os.path.abspath(config['pluginpath'])
        self.spike = config.get('spike', os.path.expanduser('~/local/bin/spike'))
        self.sail = config.get('sail', '')
        self.sail_cfg = config.get('sail_config', '')
        self.primary = config.get('primary', 'spike')

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.compile_cmd = (
            'riscv-none-elf-gcc -march={march} -mabi=ilp32 -static -mcmodel=medany '
            '-fvisibility=hidden -nostdlib -nostartfiles -g '
            '-T ' + self.pluginpath + '/env/link.ld '
            '-I ' + self.pluginpath + '/env -I ' + archtest_env + ' {macros} {test} -o ref.elf')

    def build(self, isa_yaml, platform_yaml):
        ispec = utils.load_yaml(isa_yaml)['hart0']
        self.isa = ispec['ISA'].lower()
        # RV32IMACZicsr_Zifencei_Zba -> rv32imac_zicsr_zifencei_zba
        head, _, tail = self.isa.partition('z')
        self.isa = head + ('_z' + tail if tail else '')

    def runTests(self, testList):
        mk = os.path.join(self.work_dir, 'Makefile.' + self.name[:-1])
        if os.path.exists(mk):
            os.remove(mk)
        make = utils.makeUtil(makefilePath=mk)
        make.makeCommand = 'make -k -j' + self.num_jobs
        env = ('LD_LIBRARY_PATH={0}/local/lib:{0}/local/mamba/envs/spike13/lib'
               .format(os.path.expanduser('~')))
        for name in testList:
            e = testList[name]
            sig = self.name[:-1] + '.signature'
            macros = ' '.join('-D' + m for m in e['macros'])
            cc = self.compile_cmd.format(march=march_for(e['isa']), macros=macros,
                                         test=e['test_path'])
            entry = ("$$(riscv-none-elf-nm ref.elf | "
                     "awk '/ rvtest_entry_point$$/{print \"0x\"$$1}')")
            spike = ('{env} timeout 120 {exe} --isa={isa} --priv=m --pmpregions=0 '
                     '-m0x8000:0x200000 --disable-dtb --pc={entry} '
                     '+signature=spike.signature +signature-granularity=4 ref.elf '
                     '> spike.log 2>&1').format(env=env, exe=self.spike, isa=self.isa,
                                                entry=entry)
            steps = [cc, spike]
            if self.sail:
                steps.append(
                    'timeout 120 {exe} --config {cfg} --test-signature sail.signature '
                    '--signature-granularity 4 ref.elf > sail.log 2>&1'.format(
                        exe=self.sail, cfg=self.sail_cfg))
            steps.append('cp {0}.signature {1}'.format(self.primary, sig))
            make.add_target('@cd {0}; {1}'.format(shlex.quote(e['work_dir']), ' ; '.join(steps)))
        make.execute_all(self.work_dir, timeout=7200)
