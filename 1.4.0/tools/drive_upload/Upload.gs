// Paste this whole file into a standalone Google Apps Script project.
const FOLDER_ID = 'YOUR_DRIVE_FOLDER_ID';
const MAX_BYTES = 15 * 1024 * 1024;

function setup() {
  const props = PropertiesService.getScriptProperties();
  if (!props.getProperty('UPLOAD_KEY')) {
    props.setProperty('UPLOAD_KEY', Utilities.getUuid() + Utilities.getUuid());
  }
  // Triggers Drive authorization and checks the intended folder is accessible.
  console.log('Destination: ' + DriveApp.getFolderById(FOLDER_ID).getName());
  console.log('Ready. Copy UPLOAD_KEY from Project Settings > Script properties.');
}

function doGet() {
  return json_({ok: false, error: 'Use the ABCCAD exporter to upload.'});
}

function doPost(e) {
  let lock;
  try {
    if (!e || !e.postData || e.postData.contents.length > 22 * 1024 * 1024) {
      return json_({ok: false, error: 'Invalid request size.'});
    }
    const input = JSON.parse(e.postData.contents);
    const key = PropertiesService.getScriptProperties().getProperty('UPLOAD_KEY');
    if (!key || input.key !== key) return json_({ok: false, error: 'Unauthorized.'});
    if (typeof input.name !== 'string' || !/^[A-Za-z0-9_.-]{1,180}\.stl$/.test(input.name) ||
        typeof input.data !== 'string' || input.data.length > Math.ceil(MAX_BYTES / 3) * 4 ||
        !/^[A-Za-z0-9+/]*={0,2}$/.test(input.data)) {
      return json_({ok: false, error: 'Invalid STL upload.'});
    }
    const bytes = Utilities.base64Decode(input.data);
    if (!bytes.length || bytes.length > MAX_BYTES) return json_({ok: false, error: 'Invalid STL size.'});
    // Fixed server-side destination: clients cannot write to arbitrary folders.
    lock = LockService.getScriptLock();
    if (!lock.tryLock(10000)) return json_({ok: false, error: 'Busy. Try again.'});
    const folder = DriveApp.getFolderById(FOLDER_ID);
    // Same request can be retried without duplicating a uniquely named export.
    const existing = folder.getFilesByName(input.name);
    const file = existing.hasNext() ? existing.next() :
      folder.createFile(Utilities.newBlob(bytes, 'application/octet-stream', input.name));
    return json_({ok: true, name: file.getName()});
  } catch (_) {
    return json_({ok: false, error: 'Upload failed. Check script authorization and folder access.'});
  } finally {
    if (lock && lock.hasLock()) lock.releaseLock();
  }
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}
