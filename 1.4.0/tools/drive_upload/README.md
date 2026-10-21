# Personal Quest → Google Drive exports

Destination: https://drive.google.com/drive/folders/YOUR_DRIVE_FOLDER_ID

## Authorize once on your Mac

1. Open https://script.google.com/ and create a **New project**, named ABCCAD Upload.
2. Replace the default Code.gs with all of `Upload.gs` in this directory. Save.
3. Choose **setup** in the function dropdown and click **Run**. Select the Google
   account that owns or can add files to the destination folder and approve Drive
   access. Google may show an unverified-app screen for your own unpublished
   script; review this script and proceed only if the project is yours.
4. Open **Project Settings → Script properties**. Copy `UPLOAD_KEY` into your
   local `drive_upload.cfg` (see below). Do not put it in chat or commit it.
5. **Deploy → New deployment → Select type → Web app**. Set **Execute as: Me**
   and **Who has access: Anyone**, then deploy. Copy the web app URL ending in
   `/exec`. A Google Workspace administrator may restrict anonymous deployments;
   if Anyone is unavailable, this bridge needs a different deployment/account.
6. Create `drive_upload.cfg` at the Godot project root, using the example below.
   Alternatively put it in the app's user data directory; that copy takes priority.
7. Rebuild/install the Quest APK after configuring. Both **STL · mm** for the
   selected CAD part and the main menu's combined STL export upload automatically.

```ini
[drive]
endpoint="https://script.google.com/macros/s/YOUR_DEPLOYMENT_ID/exec"
upload_key="PASTE_UPLOAD_KEY_HERE"
```

The source backup excludes this config from exports. For a personal build only, configure it locally and explicitly add it to the export include filter. It is Git-ignored.
The key grants uploads to this folder through this script, not general Drive
access. Anyone who extracts the key from your personal APK can submit uploads;
do not distribute a configured APK. To revoke access, delete the deployment or
replace UPLOAD_KEY in Script properties and update the local config/build.
Google login passwords and Google OAuth tokens are never included in the app.

## Behavior and limits

- Each successful local STL save queues one background upload. Geometry and units
  are unchanged. Existing local saves/exports remain intact.
- Upload success/failure appears through the existing export status signal.
- Local save succeeds even when offline. Export again to retry a failed upload.
  Pending uploads are in memory and do not resume after quitting the app.
- 15 MB per STL for this simple base64 bridge. Requests time out after 90 seconds.
- JSON project Save/Load is unchanged; this integration transfers STL exports.
- Apps Script redirects its JSON response to script.googleusercontent.com; the
  client follows redirects. Do not treat an HTML login page/HTTP 200 as success.
- A new Google deployment and a real Quest upload must be tested after setup.
  Local tests do not prove account authorization or headset networking.

Google documentation:
https://developers.google.com/apps-script/guides/web
https://developers.google.com/apps-script/guides/content#redirects
