//
//  ASNRequest.m
//  InternetMap
//
//  Created by Alexander on 12.12.12.
//  Copyright (c) 2012 Peer1. All rights reserved.
//

#import "ASNRequest.h"
#import <dns_sd.h>
#import "ASIFormDataRequest.h"
#import <arpa/inet.h>
#import <netdb.h>
#import "SCDispatchQueue.h"

static const int TIMEOUT = 10;

@implementation ASNRequest

+(BOOL)isInvalidOrPrivate:(NSString*)ipAddress {
    // This checks if our IP is in a reserved address space (eg. 192.168.1.1)
    NSArray* components = [ipAddress componentsSeparatedByString:@"."];
    
    if(components.count != 4) {
        return TRUE;
    }
    
    int a = [components[0] intValue];
    int b = [components[1] intValue];
    
    if (a == 10) {
        return TRUE;
    }
    
    if((a == 172) && ((b >= 16) && (b <= 31))) {
        return TRUE;
    }
    
    if((a == 192) && (b == 168)) {
        return TRUE;
    }
    
    // Probably loopback, we should ignore
    if ([ipAddress isEqualToString:@"127.255.255.255"]) {
        return TRUE;
    }
    
    return FALSE;
}

+ (void)fetchASNForIP:(NSString*)ip response:(ASNStringResponseBlock)result {
    if ([ip isEqual:[NSNull null]]) {
        // Might get a null from a timed out traceroute op, not sure if it ever actually ets this far through.
        result(nil);
    } else if ([ASNRequest isInvalidOrPrivate:ip]){
        result(nil);
    }

    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:[NSURL URLWithString:@"http://72.51.24.24:8080/iptoasn"]];
    [request setTimeOutSeconds:TIMEOUT];
    [request setRequestMethod:@"POST"];
    [request addRequestHeader:@"Content-Type" value:@"application/json"];
    
    NSString *dataString = [NSString stringWithFormat:@"{\"ip\":\"%@\"}", ip];
    [request appendPostData:[dataString dataUsingEncoding:NSUTF8StringEncoding]];
    
    __weak ASIFormDataRequest* weakRequest = request;
    
    [request setCompletionBlock:^{
        NSError* error = weakRequest.error;
        NSDictionary* jsonResponse = [NSJSONSerialization JSONObjectWithData:weakRequest.responseData options:NSJSONReadingAllowFragments error:&error];
        NSString* payload = [jsonResponse objectForKey:@"payload"];
        NSString* asnWithoutPrefix = [payload substringWithRange:NSMakeRange(2, payload.length -2)];
        result(asnWithoutPrefix);
    }];
    
    [request setFailedBlock:^{
        result(nil);
    }];

    [request start];
}


+(void)fetchIPsForASN:(NSString*)asn response:(ASNArrayResponseBlock)response {
    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:[NSURL URLWithString:@"http://72.51.24.24:8080/asntoips"]];
    [request setTimeOutSeconds:TIMEOUT];
    [request setRequestMethod:@"POST"];
    [request addRequestHeader:@"Content-Type" value:@"application/json"];
    
    NSString *dataString = [NSString stringWithFormat:@"{\"asn\":\"%@\"}", asn];
    [request appendPostData:[dataString dataUsingEncoding:NSUTF8StringEncoding]];
    
    __weak ASIFormDataRequest* weakRequest = request;

    [request setCompletionBlock:^{
        NSError* error = weakRequest.error;
        NSDictionary* jsonResponse = [NSJSONSerialization JSONObjectWithData:weakRequest.responseData options:NSJSONReadingAllowFragments error:&error];
        NSArray* offTheWire = [jsonResponse objectForKey:@"payload"];
        // We clean the array for any reserved ip spaces (sometimes 127.x.x.x shows up for loopback interfaces)
        NSMutableArray* responseArray = [[NSMutableArray alloc] init];
        for (NSString* ip in offTheWire) {
            if (![ASNRequest isInvalidOrPrivate:ip]) {
                [responseArray addObject:ip];
            } else {
                NSLog(@"Failed to add %@, was reserved IP.", ip);
            }
        }
        response(responseArray);
    }];
    
    [request setFailedBlock:^{
        response(nil);
    }];
    
    [request startAsynchronous];

}

// Get a set of IP addresses for a given host name
// Originally pulled from here: http://www.bdunagan.com/2009/11/28/iphone-tip-no-nshost/
// MIT License

+(void)fetchIPsForHostname:(NSString*)hostname response:(ASNArrayResponseBlock)result {
    [[SCDispatchQueue defaultPriorityQueue] dispatchAsync:^{
        // Get the addresses for the given hostname.
        CFHostRef hostRef = CFHostCreateWithName(kCFAllocatorDefault, (__bridge CFStringRef)hostname);
        
        BOOL isSuccess = CFHostStartInfoResolution(hostRef, kCFHostAddresses, nil);
        if (!isSuccess) {
            CFRelease(hostRef);
            [[SCDispatchQueue mainQueue] dispatchAsync:^{
                result(nil);
            }];
            return;
        }
        CFArrayRef addressesRef = CFHostGetAddressing(hostRef, nil);
        if (addressesRef == nil)  {
            CFRelease(hostRef);
            [[SCDispatchQueue mainQueue] dispatchAsync:^{
                result(nil);
            }];
            return;
        }
        // Convert these addresses into strings.
        char ipAddress[INET6_ADDRSTRLEN];
        NSMutableArray *addresses = [NSMutableArray array];
        CFIndex numAddresses = CFArrayGetCount(addressesRef);
        for (CFIndex currentIndex = 0; currentIndex < numAddresses; currentIndex++) {
            struct sockaddr *address = (struct sockaddr *)CFDataGetBytePtr(CFArrayGetValueAtIndex(addressesRef, currentIndex));
            
            if (address == nil) {
                CFRelease(hostRef);
                [[SCDispatchQueue mainQueue] dispatchAsync:^{
                    result(nil);
                }];
                return;
            }
            
            getnameinfo(address, address->sa_len, ipAddress, INET6_ADDRSTRLEN, nil, 0, NI_NUMERICHOST);
            
            if (ipAddress == nil) {
                CFRelease(hostRef);
                [[SCDispatchQueue mainQueue] dispatchAsync:^{
                    result(nil);
                }];
                return;
            }
            
            [addresses addObject:[NSString stringWithCString:ipAddress encoding:NSASCIIStringEncoding]];
        }
        
        CFRelease(hostRef);
        
        [[SCDispatchQueue mainQueue] dispatchAsync:^{
            result(addresses);
        }];
    }];
}


+ (void)fetchGlobalIPWithCompletionBlock:(ASNStringResponseBlock)completion {
    ASIFormDataRequest *request = [ASIFormDataRequest requestWithURL:[NSURL URLWithString:@"http://72.51.24.24:8080/ip"]];
    [request setTimeOutSeconds:TIMEOUT];
    [request setRequestMethod:@"POST"];
    [request addRequestHeader:@"Content-Type" value:@"application/json"];
    
    __weak ASIFormDataRequest* weakRequest = request;

    [request setCompletionBlock:^{
        NSError* error = weakRequest.error;
        NSDictionary* jsonResponse = [NSJSONSerialization JSONObjectWithData:weakRequest.responseData options:NSJSONReadingAllowFragments error:&error];
        NSString* offTheWire = [jsonResponse objectForKey:@"payload"];
        completion(offTheWire);
    }];
    
    [request setFailedBlock:^{
        completion(nil);
    }];
    
    [request startAsynchronous];
}

+(void)fetchCurrentASN:(ASNStringResponseBlock)response {
    [self fetchGlobalIPWithCompletionBlock:^(NSString *ip) {
        if(ip && ip.length) {
            [ASNRequest fetchASNForIP:ip response:response];
        }
        else {
            response(nil);
        }
    }];
}

@end
