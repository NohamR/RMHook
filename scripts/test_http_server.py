#!/usr/bin/env python3
"""
Test script for RMHook HTTP Server
Demonstrates how to trigger exports and imports via HTTP API
"""

import requests
import json
import sys

BASE_URL = "http://localhost:8080"

def test_health():
    """Test the health endpoint"""
    print("Testing /health endpoint...")
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=5)
        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False

def export_document(document_id, target_path, format_type=0, grayscale=False, 
                   keep_password=True, password="", page_selection=None):
    """
    Export a document via HTTP API
    
    Args:
        document_id: UUID of the document to export
        target_path: Target path for the export (use file:// prefix)
        format_type: Export format (0=PDF, 1=PNG, 2=SVG, 3=RmBundle, 4=RmHtml)
        grayscale: Export with grayscale pens
        keep_password: Keep password protection (for PDFs)
        password: Password for protected documents
        page_selection: List of page indices to export (None = all pages)
    """
    print(f"\nExporting document {document_id}...")
    print(f"Target: {target_path}")
    print(f"Format: {format_type}")
    
    data = {
        "target": target_path,
        "id": document_id,
        "format": format_type,
        "grayscale": grayscale,
        "keepPassword": keep_password,
        "password": password
    }
    
    if page_selection:
        data["pageSelection"] = page_selection
        print(f"Pages: {page_selection}")
    
    try:
        response = requests.post(
            f"{BASE_URL}/exportFile",
            json=data,
            timeout=10
        )
        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False

def import_document(file_url, directory_id, password=""):
    """
    Import a document via HTTP API
    
    Args:
        file_url: File URL to import (use file:// prefix)
        directory_id: UUID of the target directory
        password: Password for protected documents (optional)
    """
    print(f"\nImporting document from {file_url}...")
    print(f"Target directory: {directory_id}")
    
    data = {
        "url": file_url,
        "password": password,
        "directoryId": directory_id,
        "flag1": False,
        "flag2": False
    }
    
    try:
        response = requests.post(
            f"{BASE_URL}/documentAccepted",
            json=data,
            timeout=10
        )
        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False

def main():
    print("=" * 60)
    print("RMHook HTTP Server Test Script")
    print("=" * 60)
    
    # Test health endpoint
    if not test_health():
        print("\n❌ Health check failed. Is the server running?")
        print("Make sure reMarkable app is running with the dylib injected.")
        sys.exit(1)
    
    print("\n✅ Server is running!")
    
    # Command line interface
    if len(sys.argv) < 2:
        print("\n" + "=" * 60)
        print("Usage Examples")
        print("=" * 60)
        print("\n1. Export a document:")
        print('   python3 test_http_server.py export <doc-id> <target-path> [format] [grayscale]')
        print("\n   Example:")
        print('   python3 test_http_server.py export "abc-123" "file:///Users/noham/Desktop/test.pdf" 0 false')
        
        print("\n2. Import a document:")
        print('   python3 test_http_server.py import <file-url> <directory-id>')
        print("\n   Example:")
        print('   python3 test_http_server.py import "file:///Users/noham/Desktop/test.pdf" "2166c19d-d2cc-456c-9f0e-49482031092a"')
        
        sys.exit(0)
    
    command = sys.argv[1].lower()
    
    if command == "export" and len(sys.argv) >= 4:
        doc_id = sys.argv[2]
        target = sys.argv[3]
        format_type = int(sys.argv[4]) if len(sys.argv) > 4 else 0
        grayscale = sys.argv[5].lower() == "true" if len(sys.argv) > 5 else False
        
        success = export_document(doc_id, target, format_type, grayscale)
        if success:
            print("\n✅ Export request sent successfully!")
        else:
            print("\n❌ Export request failed!")
            sys.exit(1)
    
    elif command == "import" and len(sys.argv) >= 4:
        file_url = sys.argv[2]
        directory_id = sys.argv[3]
        password = sys.argv[4] if len(sys.argv) > 4 else ""
        
        success = import_document(file_url, directory_id, password)
        if success:
            print("\n✅ Import request sent successfully!")
        else:
            print("\n❌ Import request failed!")
            sys.exit(1)
    
    else:
        print(f"\n❌ Invalid command or missing arguments: {' '.join(sys.argv[1:])}")
        print("Run without arguments to see usage examples.")
        sys.exit(1)

if __name__ == "__main__":
    main()
