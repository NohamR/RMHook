# HTTP Server for Export Requests

The RMHook dylib includes an HTTP server that accepts export requests and forwards them to the reMarkable application via MessageBroker.

## Server Details

- **Host**: `localhost`
- **Port**: `8080`
- **Base URL**: `http://localhost:8080`

## Endpoints

### `POST /exportFile`

Trigger a document export from the reMarkable application.

**Request Body** (JSON):
```json
{
  "target": "file:///Users/username/Desktop/output.pdf",
  "id": "document-uuid-here",
  "format": 0,
  "password": "",
  "keepPassword": true,
  "grayscale": false,
  "pageSelection": []
}
```

**Parameters**:
- `target` (string, required): File path or folder URL for the export. Use `file://` prefix for local paths.
- `id` or `documentId` (string, required): The UUID of the document to export.
- `format` (integer, optional): Export format. Default: `0` (PDF)
  - `0`: PDF
  - `1`: PNG
  - `2`: SVG
  - `3`: RmBundle
  - `4`: RmHtml
- `password` (string, optional): Password for password-protected documents. Default: `""`
- `keepPassword` (boolean, optional): Whether to keep password protection on PDF exports. Default: `true`
- `grayscale` (boolean, optional): Export with grayscale pens. Default: `false`
- `pageSelection` (array, optional): Array of page indices to export. If empty or omitted, exports all pages. Example: `[0, 1, 2]`

**Response**:
```json
{
  "status": "success",
  "message": "Export request sent to application"
}
```

**Error Response**:
```json
{
  "error": "Error description"
}
```

### `POST /documentAccepted`

Import/accept a document into the reMarkable application.

**Request Body** (JSON):
```json
{
  "url": "file:///Users/username/Desktop/test.pdf",
  "password": "",
  "directoryId": "2166c19d-d2cc-456c-9f0e-49482031092a",
  "flag1": false,
  "flag2": false
}
```

**Parameters**:
- `url` (string, required): File URL to import. Use `file://` prefix for local paths.
- `password` (string, optional): Password for password-protected documents. Default: `""`
- `directoryId` (string, required): The UUID of the target directory/folder where the document should be imported.
- `flag1` (boolean, optional): Purpose unclear. Default: `false`
- `flag2` (boolean, optional): Purpose unclear. Default: `false`

**Response**:
```json
{
  "status": "success",
  "message": "Document accepted request sent to application"
}
```

**Error Response**:
```json
{
  "error": "Error description"
}
```

### `GET /health`

Health check endpoint.

**Response**:
```json
{
  "status": "ok",
  "service": "RMHook HTTP Server"
}
```

## Example Requests

### Export a document to PDF

```bash
curl -X POST http://localhost:8080/exportFile \
  -H "Content-Type: application/json" \
  -d '{
    "target": "file:///Users/noham/Desktop/export.pdf",
    "id": "12345678-1234-1234-1234-123456789abc",
    "format": 0,
    "grayscale": false,
    "keepPassword": true
  }'
```

### Export specific pages as PNG

```bash
curl -X POST http://localhost:8080/exportFile \
  -H "Content-Type: application/json" \
  -d '{
    "target": "file:///Users/noham/Desktop/pages",
    "id": "12345678-1234-1234-1234-123456789abc",
    "format": 1,
    "pageSelection": [0, 1, 2],
    "grayscale": true
  }'
```

### Export to RmBundle format

```bash
curl -X POST http://localhost:8080/exportFile \
  -H "Content-Type: application/json" \
  -d '{
    "target": "file:///Users/noham/Desktop/MyDocument",
    "id": "12345678-1234-1234-1234-123456789abc",
    "format": 3
  }'
```

### Import/Accept a document

```bash
curl -X POST http://localhost:8080/documentAccepted \
  -H "Content-Type: application/json" \
  -d '{
    "url": "file:///Users/noham/Desktop/test.pdf",
    "password": "",
    "directoryId": "2166c19d-d2cc-456c-9f0e-49482031092a",
    "flag1": false,
    "flag2": false
  }'
```

### Python Example - Export

```python
import requests
import json

# Export configuration
export_data = {
    "target": "file:///Users/noham/Desktop/output.pdf",
    "id": "12345678-1234-1234-1234-123456789abc",
    "format": 0,  # PDF
    "grayscale": False,
    "keepPassword": True
}

# Send request
response = requests.post(
    "http://localhost:8080/exportFile",
    json=export_data
)

print(f"Status: {response.status_code}")
print(f"Response: {response.json()}")
```

### Python Example - Import Document

```python
import requests

# Import configuration
import_data = {
    "url": "file:///Users/noham/Desktop/test.pdf",
    "password": "",
    "directoryId": "2166c19d-d2cc-456c-9f0e-49482031092a",
    "flag1": False,
    "flag2": False
}

# Send request
response = requests.post(
    "http://localhost:8080/documentAccepted",
    json=import_data
)

print(f"Status: {response.status_code}")
print(f"Response: {response.json()}")
```

### JavaScript Example - Export

```javascript
// Export configuration
const exportData = {
  target: "file:///Users/noham/Desktop/output.pdf",
  id: "12345678-1234-1234-1234-123456789abc",
  format: 0, // PDF
  grayscale: false,
  keepPassword: true
};

// Send request
fetch("http://localhost:8080/exportFile", {
  method: "POST",
  headers: {
    "Content-Type": "application/json"
  },
  body: JSON.stringify(exportData)
})
  .then(response => response.json())
  .then(data => console.log("Success:", data))
  .catch(error => console.error("Error:", error));
```

### JavaScript Example - Import Document

```javascript
// Import configuration
const importData = {
  url: "file:///Users/noham/Desktop/test.pdf",
  password: "",
  directoryId: "2166c19d-d2cc-456c-9f0e-49482031092a",
  flag1: false,
  flag2: false
};

// Send request
fetch("http://localhost:8080/documentAccepted", {
  method: "POST",
  headers: {
    "Content-Type": "application/json"
  },
  body: JSON.stringify(importData)
})
  .then(response => response.json())
  .then(data => console.log("Success:", data))
  .catch(error => console.error("Error:", error));
```

## Integration with QML

### Export Dialog Integration

Add the MessageBroker snippet from `docs/ExportDialog_MessageBroker_snippet.qml` to your ExportDialog.qml replacement file. This will enable the QML side to receive export requests from the HTTP server.

The MessageBroker listens for "exportFile" signals and automatically calls `PlatformHelpers.exportFile()` with the provided parameters.

### Document Import Integration

Add the MessageBroker snippet from `docs/DocumentAccepted_MessageBroker_snippet.qml` to a QML component (such as GeneralSettings.qml) that has access to PlatformHelpers. This will enable the QML side to receive document import requests from the HTTP server.

The MessageBroker listens for "documentAccepted" signals and automatically calls `PlatformHelpers.documentAccepted()` with the provided parameters.

## Document ID and Directory ID Discovery

To find document and directory IDs, you can:

1. Check the reMarkable application logs when opening documents or folders
2. Use the reMarkable Cloud API
3. Access the local database at `~/Library/Application Support/remarkable/desktop-app/`
4. For the root directory ID, check the logs when navigating to "My Files"

## Troubleshooting

- Ensure the HTTP server started successfully by checking the logs: `2025-12-08 17:32:22.288 reMarkable[19574:1316287] [HttpServer] HTTP server started successfully on http://localhost:8080`
- Test the health endpoint: `curl http://localhost:8080/health`
- Check the Console.app for detailed logging from the MessageBroker and HttpServer
- Verify the document ID and directory ID are correct UUIDs
- Ensure the target/url path is accessible and uses the `file://` prefix
- For imports, verify the target directory exists and is accessible
