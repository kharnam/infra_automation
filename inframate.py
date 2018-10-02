#!/usr/bin/env python3

"""
Usage:
    inframate.py [-h] [-y] [-v | -q ] [-m <all> | <packer> | \
<terraform> ] [ -a <plan> | <apply> | <destroy> | <build> | <rollback> ]
    inframate.py [ -m <all> ]
    inframate.py [ -m <packer> | <terraform> ]
    inframate.py [ -m <packer> ] [ -a <build> | <rollback> ]
    inframate.py [ -m <terraform> ] [ -a <plan> | <apply> | \
<destroy> ]

CLI to control Infrastructure Automation.

Arguments:
    all         All modules
    packer      Packer module
    terraform   Terraform
    plan        Execute 'terraform plan'
    apply       Execute 'terraform apply'
    destroy     Execute 'terraform destroy'
    build       Execute 'packer build'
    rollback    Execute 'packer rollback'

Options:
    -h --help
    -v --verbose  verbose mode
    -q --quiet    quiet mode
    -m    Module to call
    -a    Action to execute by module
    -y    Auto-assume 'Yes' on approval
"""

__author__ = "sergey kharnam"
__version__ = "0.0.1"

# -------------------
# Imports

import logging
import re
import subprocess
import sys

from docopt import docopt
from python_terraform import *

from inframate_data import Packer as pckr
from inframate_data import Terraform as terra


# Setup logging
log = logging.getLogger('InfraAutomation')
log.setLevel(logging.DEBUG)
# create file handler which logs even debug messages
fh = logging.FileHandler('/tmp/logs/inframate.log')
fh.setLevel(logging.DEBUG)
# create console handler with a higher log level
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)
# create formatter and add it to the handlers
formatter = logging.Formatter(
    '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
ch.setFormatter(formatter)
fh.setFormatter(formatter)
# add the handlers to logger
log.addHandler(ch)
log.addHandler(fh)

# -------------------
# System generics


def execute(*command):
    next_input = None
    for cmd in command:
        p = subprocess.Popen(cmd, stdin=next_input, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, universal_newlines=True)
        next_input = p.stdout
        for stdout_line in iter(p.stdout.readline, ""):
            yield stdout_line
        p.stdout.close()
        return_code = p.wait()
        if return_code:
            raise subprocess.CalledProcessError(return_code, cmd)


def run_command(*command):
    """
    Function to execute arbitrary series of shell commands.
    Support pipe in format: (['cmd1','args'],['cmd2', 'args'],..)
        :param *command: tupple of lists (see above)
        :return 1: if stderr has a value
    """
    if not command:
        return
    for cmd in command:
        log.debug('executing command    < {0} >'.format(cmd))
        ignored = ['\n']
        for line in execute(cmd):
            if line and line not in ignored:
                log.info(line)


# ---------------------
# Packer


def packer_validate():
    """
    Function to validate Packer templates.
    """
    log.info("Starting Packer template validation...")
    cmd = list([pckr.packer_base_cmd, 'validate'])
    cmd.extend(pckr.packer_cmd_args)
    run_command(cmd)


def packer_inspect():
    """
    Function to inspect Packer template.
    """
    log.info('Starting Packer template inspection...')
    cmd = list([pckr.packer_base_cmd, 'inspect'])
    cmd.append(pckr.packer_cmd_args[-1])
    run_command(cmd)


def packer_build():
    """
    Function to execute 'packer build'
    """
    log.info('Starting Packer image build process...')
    cmd = list([pckr.packer_base_cmd_verbose if arg['--verbose']
                else pckr.packer_base_cmd, 'build'])
    cmd.extend(pckr.packer_cmd_args)
    try:
        run_command(cmd)
    except subprocess.CalledProcessError as e:
        pass


def get_packer_images():
    cmd = "gcloud compute images list --filter='sergey' --format=json"


# TODO: implement packer_destroy()
def packer_destroy():
    """
    Function to destroy Packer applied plan.
    """
    pass


def packer_handler(action):
    """
    Function to control Packer flows
    :param action: action to perform
    :return:
    """
    packer_validate()
    log.info('------------------------------------')
    packer_inspect()
    log.info('------------------------------------')
    packer_build()


# ---------------------
# Terraform

# TODO: terraform_init
def terraform_init(trfrm):
    return_code, stdout, stderr = trfrm.init()


# TODO: terraform_plan
def terraform_plan(trfrm):
    pass


# TODO: terraform_apply
def terraform_apply(trfrm):
    pass


# TODO: terraform_destroy
def terraform_destroy(trfrm):
    pass


def terraform_handler(action):
    """
    Function to control Terraform flows
    :param action: action to perform
    :return:
    """
    trfrm = Terraform(working_dir=terra.terraform_base_dir)
    terraform_init(trfrm)
    # terraform_plan(trfrm)
    # terraform_apply(trfrm)
    # terraform_destroy(trfrm)


# ---------------------
# Main


def main(arg):
    """
    Main function
    :param arg: user input arguments
    :return:
    """
    # packer_handler(action=None)
    terraform_handler(action=None)
    print(arg)


# Execution
if __name__ == '__main__':
    arg = docopt(__doc__)
    main(arg)
