"""One-time owner-only setup. Run locally, never in a public CI job.

Requires Python 3, Java keytool, and GitHub CLI authenticated as the repository
owner. The private PKCS12 file stays at the owner-selected local path.
"""
import argparse
import base64
import getpass
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

REPO = 'xuyuanbao666/omni-video-player'
NAMES = ('OMNI_ANDROID_KEYSTORE_B64', 'OMNI_ANDROID_KEYSTORE_PASSWORD', 'OMNI_ANDROID_CERT_SHA256')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--keystore', required=True, type=Path, help='Private local path OUTSIDE the Git repository')
args = parser.parse_args()
path = args.keystore.expanduser().resolve()
repo = Path(__file__).resolve().parents[1]
if path.is_relative_to(repo):
    raise SystemExit('Choose a keystore path outside the source repository.')
if not shutil.which('keytool') or not shutil.which('gh'):
    raise SystemExit('Install a JDK and GitHub CLI, then run gh auth login.')
existing = json.loads(subprocess.check_output(['gh','secret','list','--repo',REPO,'--json','name'],text=True))
if any(s['name'] in NAMES for s in existing):
    raise SystemExit('Signing secrets already exist (or setup was interrupted). Do not rotate the key. Restore the original key and complete setup manually.')
password = getpass.getpass('Keystore password (at least 16 characters): ')
if len(password) < 16:
    raise SystemExit('Password too short.')
if not path.exists() and password != getpass.getpass('Confirm password: '):
    raise SystemExit('Passwords differ.')
env = dict(os.environ, OMNI_SETUP_PASSWORD=password)
if not path.exists():
    path.parent.mkdir(parents=True, exist_ok=True)
    # Restrict permissions on POSIX. On Windows keep the file in a private user directory.
    os.umask(0o077)
    subprocess.run(['keytool','-genkeypair','-storetype','PKCS12','-keystore',str(path),
        '-alias','omni-release','-keyalg','RSA','-keysize','3072','-validity','10000',
        '-dname','CN=Omni Video Player Release','-storepass:env','OMNI_SETUP_PASSWORD',
        '-keypass:env','OMNI_SETUP_PASSWORD'], env=env, check=True)
certificate = subprocess.check_output(['keytool','-exportcert','-storetype','PKCS12',
    '-keystore',str(path),'-alias','omni-release','-storepass:env','OMNI_SETUP_PASSWORD'], env=env)
digest = hashlib.sha256(certificate).hexdigest()
print('Public certificate SHA-256:',digest)
print('Keep an encrypted offline backup of this keystore and its password.')
if input('Upload the three signing secrets to '+REPO+'? [yes/no] ').strip().lower() != 'yes':
    raise SystemExit('No secrets uploaded.')
# Use stdin instead of command arguments or printing secret material.
for name,value in zip(NAMES,(base64.b64encode(path.read_bytes()),password.encode(),digest.encode())):
    subprocess.run(['gh','secret','set',name,'--repo',REPO],input=value,check=True)
print('Signing secrets configured. Do not delete or regenerate this key.')
