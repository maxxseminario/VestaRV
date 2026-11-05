"""RISCOF DUT plugin: the Castalia multi-hart behavioural simulation.

Each test is compiled once, then run on the hart named by `hart` in config.ini.
The target hart is one word in the flash image, so the ELF, the snapshot and the
harness are the same for every hart. A test that does not link into shared RAM,
or whose sim never delivers the full signature stream, leaves an empty signature
and RISCOF reports it failed; vesta.status in the test directory says why.
"""
import logging
import os
import shlex
import subprocess

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


def march_for(isa):
    """The test's own ISA, plus the two that gcc 13 needs spelled out."""
    m = isa.lower()
    for ext in ('zicsr', 'zifencei'):
        if ext not in m:
            m += '_' + ext
    return m


class vesta(pluginTemplate):
    __model__ = 'vesta'
    __version__ = 'castalia'

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        config = kwargs.get('config')
        if config is None:
            raise SystemExit('vesta: missing config')
        self.num_jobs = str(config.get('jobs', 4))
        self.pluginpath = os.path.abspath(config['pluginpath'])
        self.isa_spec = os.path.abspath(config['ispec'])
        self.platform_spec = os.path.abspath(config['pspec'])
        self.hart = int(config.get('hart', 0))
        self.timeout = int(config.get('timeout', 900))
        self.load = config.get('load', 'preload')
        self.simdir = os.path.join(os.path.dirname(self.pluginpath), 'sim')
        self.target_run = config.get('target_run', '1') != '0'
        # Negative-control hook: "word_index:hexvalue", applied to the
        # DUT signature after the sim, so the failure path can be shown end to end.
        self.corrupt = config.get('corrupt_signature', '')

    def initialise(self, suite, work_dir, archtest_env):
        self.work_dir = work_dir
        self.suite_dir = suite
        patched = os.path.join(work_dir, 'vesta_env')
        os.makedirs(patched, exist_ok=True)
        subprocess.check_call(['/usr/bin/python3.6', os.path.join(self.simdir, 'patch_arch_test.py'),
                               os.path.join(archtest_env, 'arch_test.h'),
                               os.path.join(patched, 'arch_test.h')])
        self.compile_cmd = (
            'riscv-none-elf-gcc -march={march} -mabi=ilp32 -static -mcmodel=medany '
            '-fvisibility=hidden -nostdlib -nostartfiles -g '
            '-T ' + self.pluginpath + '/env/link.ld '
            '-I ' + patched + ' -I ' + self.pluginpath + '/env -I ' + archtest_env + ' {macros} '
            + self.pluginpath + '/env/vesta_stub.S {test} -o dut.elf')

    def build(self, isa_yaml, platform_yaml):
        utils.load_yaml(isa_yaml)

    def runTests(self, testList):
        mk = os.path.join(self.work_dir, 'Makefile.' + self.name[:-1])
        if os.path.exists(mk):
            os.remove(mk)
        make = utils.makeUtil(makefilePath=mk)
        make.makeCommand = 'make -k -j' + self.num_jobs
        py = '/usr/bin/python3.6'
        for name in testList:
            e = testList[name]
            sig = self.name[:-1] + '.signature'
            macros = ' '.join('-D' + m for m in e['macros'])
            cc = self.compile_cmd.format(march=march_for(e['isa']), macros=macros,
                                         test=e['test_path'])
            steps = [
                'rm -f {0} vesta.status'.format(sig),
                'touch {0}'.format(sig),
                '{{ {0} > compile.log 2>&1 || {{ echo LINK_FAIL > vesta.status; exit 0; }}; }}'.format(cc),
                'mkdir -p img',
                '{0} {1}/mk_rcf.py dut.elf img/image.rcf {2} {3}'.format(py, self.simdir, self.hart, self.load),
            ]
            if self.target_run:
                steps.append(
                    '{{ {0}/run_test.sh img/image.rcf sim {1} && cp sim/signature.out {2} '
                    '&& echo SIM_OK > vesta.status || echo SIM_FAIL > vesta.status; }}'.format(
                        self.simdir, self.timeout, sig))
            if self.corrupt:
                idx, val = self.corrupt.split(':')
                steps.append("sed -i '{0}s/.*/{1}/' {2}".format(int(idx) + 1, val, sig))
            make.add_target('@cd {0}; {1}'.format(shlex.quote(e['work_dir']),
                                                  ' ; '.join(steps[:2]) + ' ; ' +
                                                  ' && '.join(steps[2:]) + ' ; true'))
        make.execute_all(self.work_dir, timeout=86400)
        if not self.target_run:
            raise SystemExit(0)
