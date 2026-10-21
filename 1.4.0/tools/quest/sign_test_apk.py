#!/usr/bin/env python3
"""Sign a local debug APK with the existing release certificate, keeping run-as.
Credentials stay in Godot's ignored local configuration; passwords are passed in
private temporary files, never command arguments or output. No device install.
"""
import argparse, configparser, json, os, pathlib, subprocess, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('apk', type=pathlib.Path)
    args = parser.parse_args()
    apk = args.apk.resolve()
    if not apk.is_file(): raise SystemExit('Build the debug APK before signing.')
    credentials = configparser.RawConfigParser()
    credentials.read(ROOT / '.godot/export_credentials.cfg')
    def value(key): return json.loads(credentials.get('preset.0.options', key))
    keystore = pathlib.Path(value('keystore/release')).expanduser()
    if not keystore.is_absolute(): keystore = ROOT / keystore
    alias = value('keystore/release_user')
    password = value('keystore/release_password')
    if not keystore.is_file() or not alias or not password:
        raise SystemExit('The configured release signing credentials are incomplete.')
    # Locate the same Android SDK configured for this project/editor.
    settings = pathlib.Path.home() / 'Library/Application Support/Godot/editor_settings-4.5.tres'
    sdk = None
    for line in settings.read_text().splitlines():
        if line.startswith('export/android/android_sdk_path = '): sdk = pathlib.Path(json.loads(line.split(' = ', 1)[1]))
    if sdk is None: raise SystemExit('Android SDK is not configured in Godot.')
    signers = sorted(sdk.glob('build-tools/*/apksigner'), key=lambda p: tuple(int(x) for x in p.parent.name.split('.') if x.isdigit()))
    if not signers: raise SystemExit('Android apksigner is not available.')
    configured = sdk / 'build-tools/35.0.0/apksigner'
    signer = configured if configured.is_file() else signers[-1]
    with tempfile.TemporaryDirectory(prefix='abccad-sign-') as temp:
        directory = pathlib.Path(temp)
        secret = directory / 'password'
        fd = os.open(secret, os.O_CREAT | os.O_WRONLY | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream: stream.write(password + '\n')
        key_secret = directory / 'key_password'
        fd = os.open(key_secret, os.O_CREAT | os.O_WRONLY | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream: stream.write(password + '\n')
        signed = directory / 'signed.apk'
        command = [str(signer), 'sign', '--ks', str(keystore), '--ks-key-alias', alias,
                   '--ks-pass', 'file:' + str(secret), '--key-pass', 'file:' + str(key_secret),
                   '--out', str(signed), str(apk)]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if result.returncode:
            detail = result.stderr.decode(errors='replace').replace(password, '[redacted]').replace(str(keystore), '[keystore]').replace(alias, '[alias]')
            raise SystemExit('APK signing failed: ' + detail[:1600])
        verified = subprocess.run([str(signer), 'verify', str(signed)], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if verified.returncode: raise SystemExit('Signed APK verification failed.')
        # Replace only this task's newly built artifact, never the keystore/config.
        import shutil
        shutil.copy2(signed, apk)
    print('Test APK signed and verified with the configured existing-app certificate.')

if __name__ == '__main__': main()
