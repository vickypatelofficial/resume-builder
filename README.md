# Resume Studio

Flutter resume editor, PDF exporter, and job-description tailoring app.

## Email auto-send backend

The app first opens the device email composer when Android or iOS has one available. If no composer is available, it can send the PDF through a configured backend. On web, configure a backend to send directly because browser mail links cannot attach files.

In the app, open **Email resume → Configure auto-send fallback** and enter the backend endpoint. An optional bearer token is stored in device secure storage.

The endpoint must accept an HTTPS `POST` request with `Content-Type: application/json` and this body:

```json
{
  "to": ["recipient@example.com"],
  "subject": "Resume",
  "body": "Please find my resume attached.",
  "attachments": [
    {
      "filename": "VICKY_PATEL_Resume.pdf",
      "contentType": "application/pdf",
      "contentBase64": "<base64 PDF bytes>"
    }
  ]
}
```

If configured, the app sends `Authorization: Bearer <token>`. Return a 2xx response only after accepting or sending the email; include a JSON `message` or `error` string for failures. For browser builds, the endpoint must allow CORS requests from the app's origin. Keep SMTP credentials and provider secrets on the backend, never in the Flutter app.
