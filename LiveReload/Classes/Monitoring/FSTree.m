
#import <sys/stat.h>
#import "FSTree.h"
#import "FSTreeFilter.h"


#define kMaxItems 100000


struct FSTreeItem {
    NSString *name;
    NSInteger parent;
    mode_t st_mode;
    dev_t st_dev;
    ino_t st_ino;
    struct timespec st_mtimespec;
};


@implementation FSTree

- (id)initWithPath:(NSString *)path filter:(FSTreeFilter *)filter {
    if ((self = [super init])) {
        _filter = [filter retain];
        _items = calloc(kMaxItems, sizeof(struct FSTreeItem));

        NSFileManager *fm = [NSFileManager defaultManager];

        NSDate *start = [NSDate date];

        struct stat st;
        if (0 == lstat([path UTF8String], &st)) {
            {
                struct FSTreeItem *item = &_items[_count++];
                item->name = [path retain];
                item->st_mode = st.st_mode & S_IFMT;
                item->st_dev = st.st_dev;
                item->st_ino = st.st_ino;
                item->st_mtimespec = st.st_mtimespec;
            }

            for (NSInteger next = 0; next < _count; ++next) {
                struct FSTreeItem *item = &_items[next];
                if (item->st_mode == S_IFDIR) {
//                    NSLog(@"Listing %@", item->name);
                    for (NSString *child in [[fm contentsOfDirectoryAtPath:item->name error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
                        if (![filter acceptsFileName:child])
                            continue;
                        NSString *subpath = [item->name stringByAppendingPathComponent:child];
                        if (0 == lstat([subpath UTF8String], &st)) {
                            struct FSTreeItem *subitem = &_items[_count++];
                            subitem->parent = next;
                            subitem->name = [subpath retain];
                            subitem->st_mode = st.st_mode & S_IFMT;
                            subitem->st_dev = st.st_dev;
                            subitem->st_ino = st.st_ino;
                            subitem->st_mtimespec = st.st_mtimespec;
                        }
                    }
                }
            }
        }

        NSDate *end = [NSDate date];
        NSLog(@"Scanned %d items in %.3lfs in directory %@", (int)_count, ([end timeIntervalSinceReferenceDate] - [start timeIntervalSinceReferenceDate]), path);
    }
    return self;
}

- (NSSet *)differenceFrom:(FSTree *)previous {
    NSMutableSet *differences = [NSMutableSet set];

    struct FSTreeItem *previtems = previous->_items;
    NSInteger prevcount = previous->_count;

    NSInteger *corresponding = malloc(_count * sizeof(NSInteger));
    NSInteger *rcorresponding = malloc(prevcount * sizeof(NSInteger));
    memset(corresponding, -1, _count * sizeof(NSInteger));
    memset(rcorresponding, -1, prevcount * sizeof(NSInteger));

    corresponding[0] = 0;
    rcorresponding[0] = 0;

    NSInteger i = 1, j = 1;
    while (i < _count && j < prevcount) {
        NSInteger cp = corresponding[_items[i].parent];
        if (cp < 0) {
            NSLog(@"%@ is a subitem of a new item", _items[i].name);
            corresponding[i] = -1;
            ++i;
        } else if (previtems[j].parent < cp) {
            NSLog(@"%@ is a deleted item", previtems[j].name);
            rcorresponding[j] = -1;
            ++j;
        } else if (previtems[j].parent > cp) {
            NSLog(@"%@ is a new item", _items[i].name);
            corresponding[i] = -1;
            ++i;
        } else {
            NSComparisonResult r = [_items[i].name compare:previtems[j].name];
            if (r == 0) {
                // same item! compare mod times
                if (_items[i].st_mode == previtems[j].st_mode && _items[i].st_dev == previtems[j].st_dev && _items[i].st_ino == previtems[j].st_ino && _items[i].st_mtimespec.tv_sec == previtems[j].st_mtimespec.tv_sec && _items[i].st_mtimespec.tv_nsec == previtems[j].st_mtimespec.tv_nsec) {
                    // unchanged
//                    NSLog(@"%@ is unchanged item", _items[i].name);
                } else {
                    // changed
                    NSLog(@"%@ is changed item", _items[i].name);
                    if (_items[i].st_mode == S_IFREG || previtems[j].st_mode == S_IFREG) {
                        [differences addObject:_items[i].name];
                    }
                }
                corresponding[i] = j;
                rcorresponding[j] = i;
                ++i;
                ++j;
            } else if (r > 0) {
                // i is after j => we need to advance j => j is deleted
                NSLog(@"%@ is a deleted item", previtems[j].name);
                rcorresponding[j] = -1;
                ++j;
            } else /* if (r < 0) */ {
                // i is before j => we need to advance i => i is new
                NSLog(@"%@ is a new item", _items[i].name);
                corresponding[i] = -1;
                ++i;
            }
        }
    }
    // for any tail left, we've already filled it in with -1's

    for (i = 0; i < _count; i++) {
        if (corresponding[i] < 0) {
            if (_items[i].st_mode == S_IFREG) {
                [differences addObject:_items[i].name];
            }
        }
    }
    for (j = 0; j < prevcount; j++) {
        if (rcorresponding[j] < 0) {
            if (previtems[j].st_mode == S_IFREG) {
                [differences addObject:previtems[j].name];
            }
        }
    }

    free(corresponding);
    free(rcorresponding);

    return differences;
}

@end