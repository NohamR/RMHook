#ifndef ResourceUtils_h
#define ResourceUtils_h

#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

struct ResourceRoot {
    uint8_t *data;
    uint8_t *name;
    uint8_t *tree;
    size_t treeSize;
    size_t dataSize;
    size_t originalDataSize;
    size_t nameSize;
    int entriesAffected;
};

// Replacement entry for storing new data to be appended
struct ReplacementEntry {
    int node;
    uint8_t *data;
    size_t size;
    size_t copyToOffset;
    bool freeAfterwards;
    struct ReplacementEntry *next;
};

#define TREE_ENTRY_SIZE 22
#define DIRECTORY 0x02

// Read/Write utilities
uint32_t readUInt32(uint8_t *addr, int offset);
uint16_t readUInt16(uint8_t *addr, int offset);
void writeUint32(uint8_t *addr, int offset, uint32_t value);
void writeUint16(uint8_t *addr, int offset, uint16_t value);

// Resource tree utilities
int findOffset(int node);
void nameOfChild(struct ResourceRoot *root, int node, int *size, char *buffer, int max);
void statArchive(struct ResourceRoot *root, int node);
void processNode(struct ResourceRoot *root, int node, const char *rootName);
void ReMarkableDumpResourceFile(struct ResourceRoot *root, int node, const char *rootName, const char *fileName, uint16_t flags);

// Replacement utilities
void addReplacementEntry(struct ReplacementEntry *entry);
struct ReplacementEntry *getReplacementEntries(void);
void clearReplacementEntries(void);
void replaceNode(struct ResourceRoot *root, int node, const char *fullPath, int treeOffset);

#ifdef __cplusplus
}
#endif

#endif
