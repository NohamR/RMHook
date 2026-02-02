#import "ResourceUtils.h"
#import "Logger.h"
#import <Foundation/Foundation.h>
#import <string.h>
#import <dispatch/dispatch.h>
#import <zstd.h>
#import <zlib.h>

static NSString *ReMarkableDumpRootDirectory(void);
static NSString *ReMarkablePreferencesDirectory(void);

static NSString *ReMarkablePreferencesDirectory(void) {
    NSArray<NSString *> *libraryPaths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
    NSString *libraryDir = [libraryPaths firstObject];
    if (![libraryDir length]) {
        libraryDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Library"];
    }
    return [libraryDir stringByAppendingPathComponent:@"Preferences"];
}

static NSString *ReMarkableDumpRootDirectory(void) {
    static NSString *dumpDirectory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *preferencesDir = ReMarkablePreferencesDirectory();
        NSString *candidate = [preferencesDir stringByAppendingPathComponent:@"dump"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error = nil;
        if (![fileManager fileExistsAtPath:candidate]) {
            if (![fileManager createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLogger(@"[reMarkable] Failed to create dump directory %@: %@", candidate, error);
            }
        }
        dumpDirectory = [candidate copy];
    });
    return dumpDirectory;
}

#ifdef BUILD_MODE_QMLREBUILD
uint32_t readUInt32(uint8_t *addr, int offset) {
    return (uint32_t)(addr[offset + 0] << 24) |
           (uint32_t)(addr[offset + 1] << 16) |
           (uint32_t)(addr[offset + 2] << 8) |
           (uint32_t)(addr[offset + 3] << 0);
}

void writeUint32(uint8_t *addr, int offset, uint32_t value) {
    addr[offset + 0] = (uint8_t)(value >> 24);
    addr[offset + 1] = (uint8_t)(value >> 16);
    addr[offset + 2] = (uint8_t)(value >> 8);
    addr[offset + 3] = (uint8_t)(value >> 0);
}

void writeUint16(uint8_t *addr, int offset, uint16_t value) {
    addr[offset + 0] = (uint8_t)(value >> 8);
    addr[offset + 1] = (uint8_t)(value >> 0);
}

uint16_t readUInt16(uint8_t *addr, int offset) {
    return (uint16_t)((addr[offset + 0] << 8) |
                      (addr[offset + 1] << 0));
}

int findOffset(int node) {
    return node * TREE_ENTRY_SIZE;
}

void statArchive(struct ResourceRoot *root, int node) {
    int offset = findOffset(node);
    int thisMaxLength = offset + TREE_ENTRY_SIZE;
    if (thisMaxLength > (int)root->treeSize) root->treeSize = (size_t)thisMaxLength;
    uint32_t nameOffset = readUInt32(root->tree, offset);
    uint32_t thisMaxNameLength = nameOffset + readUInt16(root->name, (int)nameOffset);
    if (thisMaxNameLength > root->nameSize) root->nameSize = thisMaxNameLength;
    int flags = readUInt16(root->tree, offset + 4);
    if (!(flags & DIRECTORY)) {
        uint32_t dataOffset = readUInt32(root->tree, offset + 4 + 2 + 4);
        uint32_t dataSize = readUInt32(root->data, (int)dataOffset);
        uint32_t thisMaxDataLength = dataOffset + dataSize + 4;
        if (thisMaxDataLength > root->dataSize) root->dataSize = thisMaxDataLength;
    } else {
        uint32_t childCount = readUInt32(root->tree, offset + 4 + 2);
        offset += 4 + 4 + 2;
        uint32_t childOffset = readUInt32(root->tree, offset);
        for (int child = (int)childOffset; child < (int)(childOffset + childCount); child++){
            statArchive(root, child);
        }
    }
    root->originalDataSize = root->dataSize;
}

void nameOfChild(struct ResourceRoot *root, int node, int *size, char *buffer, int max) {
    if (!buffer || max <= 0) {
        if (size) {
            *size = 0;
        }
        return;
    }

    if (!root || !root->tree || !root->name) {
        if (size) {
            *size = 0;
        }
        buffer[0] = '\0';
        return;
    }

    if (!node) {
        if (size) {
            *size = 0;
        }
        buffer[0] = '\0';
        return;
    }

    const int offset = findOffset(node);
    uint32_t nameOffset = readUInt32(root->tree, offset);
    uint16_t nameLength = readUInt16(root->name, (int)nameOffset);

    if (nameLength > (uint16_t)(max - 1)) {
        nameLength = (uint16_t)(max - 1);
    }

    nameOffset += 2;      // skip length prefix
    nameOffset += 4;      // skip hash

    if (size) {
        *size = (int)nameLength;
    }

    for (int i = 1; i < (int)nameLength * 2; i += 2) {
        buffer[i / 2] = ((const char *)root->name)[nameOffset + i];
    }
    buffer[nameLength] = '\0';
}

void ReMarkableDumpResourceFile(struct ResourceRoot *root, int node, const char *rootName, const char *fileName, uint16_t flags) {
    if (!root || !root->tree || !root->data || !fileName) {
        return;
    }

    const int baseOffset = findOffset(node);
    const uint32_t dataOffset = readUInt32(root->tree, baseOffset + 4 + 2 + 4);
    const uint32_t dataSize = readUInt32(root->data, (int)dataOffset);
    if (dataSize == 0) {
        return;
    }

    const uint32_t payloadStart = dataOffset + 4;
    if (root->dataSize && (payloadStart + dataSize) > root->dataSize) {
        NSLogger(@"[reMarkable] Skipping dump for node %d due to size mismatch (%u bytes beyond bounds)", (int)node, dataSize);
        return;
    }

    const uint8_t *payload = root->data + payloadStart;
    uint8_t *ownedBuffer = NULL;
    size_t bytesToWrite = dataSize;

    if (flags == 4) {
        size_t expectedSize = ZSTD_getFrameContentSize(payload, dataSize);
        if (expectedSize == ZSTD_CONTENTSIZE_ERROR) {
            NSLogger(@"[reMarkable] ZSTD frame content size error for node %d", (int)node);
            return;
        }

        size_t bufferSize;
        if (expectedSize == ZSTD_CONTENTSIZE_UNKNOWN) {
            if ((size_t)dataSize > SIZE_MAX / 4) {
                bufferSize = (size_t)dataSize;
            } else {
                bufferSize = (size_t)dataSize * 4;
            }
        } else {
            bufferSize = expectedSize;
        }
        if (bufferSize < (size_t)dataSize) {
            bufferSize = (size_t)dataSize;
        }

        if (bufferSize > SIZE_MAX - 1) {
            NSLogger(@"[reMarkable] ZSTD decompression size too large for node %d", (int)node);
            return;
        }

        for (int attempt = 0; attempt < 6; ++attempt) {
            ownedBuffer = (uint8_t *)malloc(bufferSize + 1);
            if (!ownedBuffer) {
                NSLogger(@"[reMarkable] Failed to allocate %zu bytes for ZSTD decompression", bufferSize + 1);
                return;
            }

            size_t decompressedSize = ZSTD_decompress(ownedBuffer, bufferSize, payload, dataSize);
            if (!ZSTD_isError(decompressedSize)) {
                bytesToWrite = decompressedSize;
                ownedBuffer[bytesToWrite] = 0;
                break;
            }

            ZSTD_ErrorCode errorCode = ZSTD_getErrorCode(decompressedSize);
            free(ownedBuffer);
            ownedBuffer = NULL;

            if (errorCode == ZSTD_error_dstSize_tooSmall) {
                if (bufferSize > SIZE_MAX / 2) {
                    NSLogger(@"[reMarkable] ZSTD decompression buffer would overflow for node %d", (int)node);
                    return;
                }
                bufferSize *= 2;
                continue;
            }

            NSLogger(@"[reMarkable] ZSTD decompression failed for node %d: %s", (int)node, ZSTD_getErrorName(decompressedSize));
            return;
        }

        if (!ownedBuffer) {
            NSLogger(@"[reMarkable] ZSTD decompression exhausted retries for node %d", (int)node);
            return;
        }
    } else if (flags == 0) {
        if ((size_t)dataSize > SIZE_MAX - 1) {
            NSLogger(@"[reMarkable] Raw resource size too large for node %d", (int)node);
            return;
        }
        ownedBuffer = (uint8_t *)malloc((size_t)dataSize + 1);
        if (!ownedBuffer) {
            NSLogger(@"[reMarkable] Failed to allocate %u bytes for raw copy", (unsigned)(dataSize + 1u));
            return;
        }
        memcpy(ownedBuffer, payload, dataSize);
        ownedBuffer[dataSize] = 0;
        bytesToWrite = dataSize;

    } else if (flags == 1) {
        if (dataSize <= 4) {
            NSLogger(@"[reMarkable] Zlib compressed resource too small for node %d", (int)node);
            return;
        }

        const uint32_t expectedSize =
            ((uint32_t)payload[0] << 24) |
            ((uint32_t)payload[1] << 16) |
            ((uint32_t)payload[2] << 8) |
            ((uint32_t)payload[3] << 0);

        if (!expectedSize) {
            NSLogger(@"[reMarkable] Zlib resource reported zero size for node %d", (int)node);
            return;
        }

        const uint8_t *compressedPayload = payload + 4;
        const size_t compressedSize = (size_t)dataSize - 4;
        if (compressedSize > UINT_MAX) {
            NSLogger(@"[reMarkable] Zlib compressed payload too large for node %d", (int)node);
            return;
        }

        z_stream stream;
        memset(&stream, 0, sizeof(stream));
        stream.next_in = (Bytef *)compressedPayload;
        stream.avail_in = (uInt)compressedSize;

        int status = inflateInit(&stream);
        if (status != Z_OK) {
            NSLogger(@"[reMarkable] Failed to initialize zlib for node %d: %d", (int)node, status);
            return;
        }

        ownedBuffer = (uint8_t *)malloc((size_t)expectedSize + 1);
        if (!ownedBuffer) {
            NSLogger(@"[reMarkable] Failed to allocate %u bytes for zlib decompression", (unsigned)expectedSize + 1u);
            inflateEnd(&stream);
            return;
        }

        stream.next_out = ownedBuffer;
        stream.avail_out = (uInt)expectedSize;

        status = inflate(&stream, Z_FINISH);
        if (status != Z_STREAM_END) {
            NSLogger(@"[reMarkable] Zlib decompression failed for node %d with status %d", (int)node, status);
            free(ownedBuffer);
            ownedBuffer = NULL;
            inflateEnd(&stream);
            return;
        }

        bytesToWrite = (size_t)stream.total_out;
        inflateEnd(&stream);
        ownedBuffer[bytesToWrite] = 0;
    } else {
        NSLogger(@"[reMarkable] Unknown compression flag %u for node %d; skipping dump", flags, (int)node);
        return;
    }

    NSString *dumpRoot = ReMarkableDumpRootDirectory();
    if (![dumpRoot length]) {
        if (ownedBuffer) {
            free(ownedBuffer);
        }
        return;
    }

    NSString *rootComponent = [NSString stringWithUTF8String:rootName ? rootName : ""];
    NSString *fileComponent = [NSString stringWithUTF8String:fileName];
    if (!rootComponent) {
        rootComponent = @"";
    }
    if (!fileComponent) {
        fileComponent = @"";
    }

    NSString *relativePath = [rootComponent stringByAppendingString:fileComponent];
    if ([relativePath hasPrefix:@"/"]) {
        relativePath = [relativePath substringFromIndex:1];
    }
    if (![relativePath length]) {
        return;
    }

    NSString *fullPath = [dumpRoot stringByAppendingPathComponent:relativePath];
    NSString *directoryPath = [fullPath stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *directoryError = nil;
    if ([directoryPath length] && ![fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        NSLogger(@"[reMarkable] Failed to create directory for dump %@: %@", directoryPath, directoryError);
        if (ownedBuffer) {
            free(ownedBuffer);
        }
        return;
    }

    const void *dataSource = ownedBuffer ? (const void *)ownedBuffer : (const void *)payload;
    NSData *dataObject = [NSData dataWithBytes:dataSource length:bytesToWrite];
    NSError *writeError = nil;
    if (![dataObject writeToFile:fullPath options:NSDataWritingAtomic error:&writeError]) {
        NSLogger(@"[reMarkable] Failed to write dump file %@: %@", fullPath, writeError);
    } else {
        NSLogger(@"[reMarkable] Dumped resource to %@ (%zu bytes)", fullPath, bytesToWrite);
    }

    if (ownedBuffer) {
        free(ownedBuffer);
    }
}

// List of files to process with replaceNode
static const char *kFilesToReplace[] = {
    "/qml/client/dialogs/ExportDialog.qml",
    "/qml/client/settings/GeneralSettings.qml",
    "/qml/client/dialogs/ExportUtils.js",
    "/qml/client/desktop/FileImportDialog.qml",
    NULL  // Sentinel to mark end of list
};

static bool shouldReplaceFile(const char *fullPath) {
    if (!fullPath) return false;
    for (int i = 0; kFilesToReplace[i] != NULL; i++) {
        if (strcmp(fullPath, kFilesToReplace[i]) == 0) {
            return true;
        }
    }
    return false;
}

// Get the path to replacement files directory
static NSString *ReMarkableReplacementDirectory(void) {
    static NSString *replacementDirectory = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *preferencesDir = ReMarkablePreferencesDirectory();
        NSString *candidate = [preferencesDir stringByAppendingPathComponent:@"replacements"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSError *error = nil;
        if (![fileManager fileExistsAtPath:candidate]) {
            if (![fileManager createDirectoryAtPath:candidate withIntermediateDirectories:YES attributes:nil error:&error]) {
                NSLogger(@"[reMarkable] Failed to create replacements directory %@: %@", candidate, error);
            }
        }
        replacementDirectory = [candidate copy];
    });
    return replacementDirectory;
}

// Global linked list of replacement entries
static struct ReplacementEntry *g_replacementEntries = NULL;

void addReplacementEntry(struct ReplacementEntry *entry) {
    entry->next = g_replacementEntries;
    g_replacementEntries = entry;
}

struct ReplacementEntry *getReplacementEntries(void) {
    return g_replacementEntries;
}

void clearReplacementEntries(void) {
    struct ReplacementEntry *current = g_replacementEntries;
    while (current) {
        struct ReplacementEntry *next = current->next;
        if (current->freeAfterwards && current->data) {
            free(current->data);
        }
        free(current);
        current = next;
    }
    g_replacementEntries = NULL;
}

void replaceNode(struct ResourceRoot *root, int node, const char *fullPath, int treeOffset) {
    NSLogger(@"[reMarkable] replaceNode called for: %s", fullPath);
    
    if (!root || !root->tree || !fullPath) {
        NSLogger(@"[reMarkable] replaceNode: invalid parameters");
        return;
    }
    
    // Build path to replacement file on disk
    NSString *replacementDir = ReMarkableReplacementDirectory();
    if (![replacementDir length]) {
        NSLogger(@"[reMarkable] replaceNode: no replacement directory");
        return;
    }
    
    NSString *relativePath = [NSString stringWithUTF8String:fullPath];
    if ([relativePath hasPrefix:@"/"]) {
        relativePath = [relativePath substringFromIndex:1];
    }
    
    NSString *replacementFilePath = [replacementDir stringByAppendingPathComponent:relativePath];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:replacementFilePath]) {
        NSLogger(@"[reMarkable] replaceNode: replacement file not found at %@", replacementFilePath);
        return;
    }
    
    // Read the replacement file
    NSError *readError = nil;
    NSData *replacementData = [NSData dataWithContentsOfFile:replacementFilePath options:0 error:&readError];
    if (!replacementData || readError) {
        NSLogger(@"[reMarkable] replaceNode: failed to read replacement file %@: %@", replacementFilePath, readError);
        return;
    }
    
    size_t dataSize = [replacementData length];
    NSLogger(@"[reMarkable] replaceNode: loaded replacement file %@ (%zu bytes)", replacementFilePath, dataSize);
    
    // Allocate and copy the replacement data
    uint8_t *newData = (uint8_t *)malloc(dataSize);
    if (!newData) {
        NSLogger(@"[reMarkable] replaceNode: failed to allocate %zu bytes", dataSize);
        return;
    }
    memcpy(newData, [replacementData bytes], dataSize);
    
    // Create a replacement entry
    struct ReplacementEntry *entry = (struct ReplacementEntry *)malloc(sizeof(struct ReplacementEntry));
    if (!entry) {
        NSLogger(@"[reMarkable] replaceNode: failed to allocate replacement entry");
        free(newData);
        return;
    }
    
    entry->node = node;
    entry->data = newData;
    entry->size = dataSize;
    entry->freeAfterwards = true;
    entry->copyToOffset = root->dataSize;  // Will be appended at the end of data
    entry->next = NULL;
    
    // Update the tree entry:
    writeUint16(root->tree, treeOffset - 2, 0);  // Set flag to raw (uncompressed)
    writeUint32(root->tree, treeOffset + 4, (uint32_t)entry->copyToOffset);  // Update data offset
    
    NSLogger(@"[reMarkable] replaceNode: updated tree - flags at offset %d, dataOffset at offset %d -> %zu", 
             treeOffset - 2, treeOffset + 4, entry->copyToOffset);
    
    // Update dataSize to account for the new data (size prefix + data)
    root->dataSize += entry->size + 4;
    root->entriesAffected++;
    
    // Add to replacement entries list
    addReplacementEntry(entry);
    
    NSLogger(@"[reMarkable] replaceNode: marked for replacement - %s (new offset: %zu, size: %zu)", 
             fullPath, entry->copyToOffset, entry->size);
}

void processNode(struct ResourceRoot *root, int node, const char *rootName) {
    int offset = findOffset(node) + 4;
    uint16_t flags = readUInt16(root->tree, offset);
    offset += 2;
    int stringLength = 0;
    char nameBuffer[256];
    nameOfChild(root, node, &stringLength, nameBuffer, (int)sizeof(nameBuffer));

    if (flags & DIRECTORY) {
        uint32_t childCount = readUInt32(root->tree, offset);
        offset += 4;
        uint32_t childOffset = readUInt32(root->tree, offset);
        const size_t rootLength = rootName ? strlen(rootName) : 0;
        char *tempRoot = (char *)malloc(rootLength + (size_t)stringLength + 2);
        if (!tempRoot) {
            return;
        }

        if (rootLength > 0) {
            memcpy(tempRoot, rootName, rootLength);
        }
        memcpy(tempRoot + rootLength, nameBuffer, (size_t)stringLength);
        tempRoot[rootLength + stringLength] = '/';
        tempRoot[rootLength + stringLength + 1] = '\0';

        for (uint32_t child = childOffset; child < childOffset + childCount; ++child) {
            processNode(root, (int)child, tempRoot);
        }

        free(tempRoot);
    } else {
        uint16_t fileFlag = readUInt16(root->tree, offset - 2);
        const char *type;
        if (fileFlag == 1) {
            type = "zlib";
        } else if (fileFlag == 4) {
            type = "zstd";
        } else if (fileFlag == 0) {
            type = "raw";
        } else {
            type = "unknown";
        }
        
        // Build full path: rootName + nameBuffer
        const size_t rootLen = rootName ? strlen(rootName) : 0;
        const size_t nameLen = strlen(nameBuffer);
        char *fullPath = (char *)malloc(rootLen + nameLen + 1);
        if (fullPath) {
            if (rootLen > 0) {
                memcpy(fullPath, rootName, rootLen);
            }
            memcpy(fullPath + rootLen, nameBuffer, nameLen);
            fullPath[rootLen + nameLen] = '\0';
            
            NSLogger(@"[reMarkable] Processing node %d: %s (type: %s)", (int)node, fullPath, type);
            
            // Check if this file should be replaced
            if (shouldReplaceFile(fullPath)) {
                replaceNode(root, node, fullPath, offset);
            }
            
            free(fullPath);
        } else {
            NSLogger(@"[reMarkable] Processing node %d: %s%s (type: %s)", (int)node, rootName ? rootName : "", nameBuffer, type);
        }
        
        // ReMarkableDumpResourceFile(root, node, rootName ? rootName : "", nameBuffer, fileFlag);
    }
}
#endif // BUILD_MODE_QMLREBUILD