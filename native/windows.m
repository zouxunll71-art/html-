#import <AppKit/AppKit.h>
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 4) return 2;
    NSString *action = @(argv[1]);
    NSArray *paths = @[@(argv[2]), @(argv[3])];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSUInteger i=0; i<paths.count; i++) {
        NSString *path = [paths[i] stringByStandardizingPath];
        NSString *key = i == 0 ? @"studio" : @"simulator";
        NSRunningApplication *match = nil;
        for (NSRunningApplication *app in NSWorkspace.sharedWorkspace.runningApplications) {
            if ([[app.bundleURL.path stringByStandardizingPath] isEqualToString:path]) { match=app; break; }
        }
        if (match && [action isEqualToString:@"hide"]) [match hide];
        result[key] = @{@"running": @(match != nil), @"hidden": @(match == nil || match.hidden)};
    }
    NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    fwrite(data.bytes,1,data.length,stdout); fputc('\n',stdout);
    return 0;
}}
