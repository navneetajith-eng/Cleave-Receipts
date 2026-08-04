import requests
import json
import base64

# Download a sample receipt image
response = requests.get('https://raw.githubusercontent.com/Azure-Samples/cognitive-services-REST-api-samples/master/curl/form-recognizer/contoso-receipt.png')
with open('receipt.png', 'wb') as f:
    f.write(response.content)

# Test the backend API
url = "http://localhost:8000/api/receipts?group_id=123"
files = {'file': ('receipt.png', open('receipt.png', 'rb'), 'image/png')}

try:
    res = requests.post(url, files=files)
    print(res.status_code)
    print(res.json())
except Exception as e:
    print(e)
