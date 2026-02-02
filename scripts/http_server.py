#!/usr/bin/env python3
import requests
import json
import sys
import argparse

BASE_URL = "http://localhost:8080"

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

def import_document(file_url, directory_id, password="", flag1=False, flag2=False):
    """
    Import a document via HTTP API
    
    Args:
        file_url: File URL to import (use file:// prefix)
        directory_id: UUID of the target directory
        password: Password for protected documents (optional)
        flag1: Additional flag parameter
        flag2: Additional flag parameter
    """
    print(f"\nImporting document from {file_url}...")
    print(f"Target directory: {directory_id}")
    
    data = {
        "url": file_url,
        "password": password,
        "directoryId": directory_id,
        "flag1": flag1,
        "flag2": flag2
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
    parser = argparse.ArgumentParser(
        description='reMarkable HTTP Server API Client',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  Export a document as PDF:
    %(prog)s export 12345678-1234-1234-1234-123456789abc file:///Users/noham/Desktop/test.pdf
  
  Export as PNG with grayscale:
    %(prog)s export <doc-id> <target> --format 1 --grayscale
  
  Export specific pages:
    %(prog)s export <doc-id> <target> --pages 0 1 2
  
  Import a document:
    %(prog)s import file:///Users/noham/Desktop/test.pdf 2166c19d-d2cc-456c-9f0e-49482031092a
  
  Import with password:
    %(prog)s import <file-url> <directory-id> --password mypassword
        '''
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Export command
    export_parser = subparsers.add_parser('export', help='Export a document')
    export_parser.add_argument('document_id', help='UUID of the document to export')
    export_parser.add_argument('target_path', help='Target path for export (use file:// prefix)')
    export_parser.add_argument(
        '--format', '-f',
        type=int,
        default=0,
        choices=[0, 1, 2, 3, 4],
        help='Export format: 0=PDF, 1=PNG, 2=SVG, 3=RmBundle, 4=RmHtml (default: 0)'
    )
    export_parser.add_argument(
        '--grayscale', '-g',
        action='store_true',
        help='Export with grayscale pens'
    )
    export_parser.add_argument(
        '--no-keep-password',
        action='store_true',
        help='Do not keep password protection (for PDFs)'
    )
    export_parser.add_argument(
        '--password', '-p',
        default='',
        help='Password for protected documents'
    )
    export_parser.add_argument(
        '--pages',
        type=int,
        nargs='+',
        help='List of page indices to export (default: all pages)'
    )
    
    # Import command
    import_parser = subparsers.add_parser('import', help='Import a document')
    import_parser.add_argument('file_url', help='File URL to import (use file:// prefix)')
    import_parser.add_argument('directory_id', help='UUID of the target directory')
    import_parser.add_argument(
        '--password', '-p',
        default='',
        help='Password for protected documents'
    )
    import_parser.add_argument(
        '--flag1',
        action='store_true',
        help='Additional flag parameter'
    )
    import_parser.add_argument(
        '--flag2',
        action='store_true',
        help='Additional flag parameter'
    )
    
    args = parser.parse_args()
    
    if args.command == 'export':
        success = export_document(
            document_id=args.document_id,
            target_path=args.target_path,
            format_type=args.format,
            grayscale=args.grayscale,
            keep_password=not args.no_keep_password,
            password=args.password,
            page_selection=args.pages
        )
        if success:
            print("\n✅ Export request sent successfully!")
        else:
            print("\n❌ Export request failed!")
            sys.exit(1)
    elif args.command == 'import':
        success = import_document(
            file_url=args.file_url,
            directory_id=args.directory_id,
            password=args.password,
            flag1=args.flag1,
            flag2=args.flag2
        )
        if success:
            print("\n✅ Import request sent successfully!")
        else:
            print("\n❌ Import request failed!")
            sys.exit(1)
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
