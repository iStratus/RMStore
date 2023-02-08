//
//  RMStoreAppReceiptVerifier.m
//  RMStore
//
//  Created by Hermes on 10/15/13.
//  Copyright (c) 2013 Robot Media. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#import "RMStoreAppReceiptVerifier.h"
#import "RMAppReceipt.h"

@implementation RMStoreAppReceiptVerifier

- (void)verifyTransaction:(SKPaymentTransaction*)transaction
				  success:(void (^)(void))successBlock
                           failure:(void (^)(NSError *error))failureBlock
{
    RMAppReceipt *receipt = [RMAppReceipt bundleReceipt];
    const BOOL verified = [self verifyTransaction:transaction inReceipt:receipt success:successBlock failure:nil]; // failureBlock is nil intentionally. See below.
    if (verified) return;

    // Apple recommends to refresh the receipt if validation fails on iOS
    [[RMStore defaultStore] refreshReceiptOnSuccess:^{
        RMAppReceipt *receipt = [RMAppReceipt bundleReceipt];
        [self verifyTransaction:transaction inReceipt:receipt success:successBlock failure:failureBlock];
    } failure:^(NSError *error) {
        [self failWithBlock:failureBlock error:error];
    }];
}

- (RMAppReceipt *)verifiedAppReceipt:(NSError **)error
{
    RMAppReceipt *receipt = [RMAppReceipt bundleReceipt];
	if ([self verifyAppReceipt:receipt error:error]) {
		return receipt;
	}
	return nil;
}

#pragma mark - Properties

- (NSString*)bundleIdentifier
{
    if (!_bundleIdentifier)
    {
        return [NSBundle mainBundle].bundleIdentifier;
    }
    return _bundleIdentifier;
}

- (NSString*)bundleVersion
{
    if (!_bundleVersion)
    {
#if TARGET_OS_IPHONE
        return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
#else
        return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
#endif
    }
    return _bundleVersion;
}

#pragma mark - Private

- (BOOL)verifyAppReceipt:(RMAppReceipt*)receipt error:(NSError **)error
{
	NSMutableArray<NSError *> *const errors = (error != NULL ? [NSMutableArray arrayWithCapacity:4] : nil);
	if (receipt == nil) {
		if (errors == nil) {
			return NO;
		}
		[errors addObject:[NSError errorWithDomain: RMStoreAppReceiptVerifierErrorDomain
											  code: RMStoreAppReceiptVerificationErrorNilReceipt
										  userInfo: @{
			NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Nil Receipt", @"Nil Receipt"),
		}]];
	}
	
	if (![receipt.bundleIdentifier isEqualToString:self.bundleIdentifier]) {
		if (errors == nil) {
			return NO;
		}
		[errors addObject:[NSError errorWithDomain: RMStoreAppReceiptVerifierErrorDomain
											  code: RMStoreAppReceiptVerificationErrorBundleIdentifierMismatch
										  userInfo: @{
			NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Bundle Identifier Mismatch", @"Bundle Identifier Mismatch"),
			NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ != %@", receipt.bundleIdentifier, self.bundleIdentifier],
		}]];
	}
	
	if (![receipt.appVersion isEqualToString:self.bundleVersion]) {
		if (errors == nil) {
			return NO;
		}
		[errors addObject:[NSError errorWithDomain: RMStoreAppReceiptVerifierErrorDomain
											  code: RMStoreAppReceiptVerificationErrorBundleVersionMismatch
										  userInfo: @{
			NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"App Version Mismatch", @"App Version Mismatch"),
			NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ != %@", receipt.appVersion, self.bundleVersion],
		}]];
	}
	
	if (![receipt verifyReceiptHash]) {
		if (errors == nil) {
			return NO;
		}
		[errors addObject:[NSError errorWithDomain: RMStoreAppReceiptVerifierErrorDomain
											  code: RMStoreAppReceiptVerificationErrorInvalidHash
										  userInfo: @{
			NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Verify Receipt Failure", @"Verify Receipt Failure"),
		}]];
	}
	
	if (error == NULL) {
		return YES;
	}
	if (@available(iOS 14.5, *)) {
		switch (errors.count) {
			case 0:
				*error = nil;
				break;
			case 1:
				*error = errors[0];
				break;
			default:
				*error = [NSError errorWithDomain: RMStoreAppReceiptVerifierErrorDomain
											 code: RMStoreAppReceiptVerificationErrorMultiple
										 userInfo: @{
					NSLocalizedFailureReasonErrorKey: NSLocalizedString(@"Multiple Errors Occurred", @"Multiple Errors Occurred"),
					NSMultipleUnderlyingErrorsKey: errors,
				}];
				break;
		}
	} else {
		*error = errors.firstObject;
	}
	return (*error == nil);
}

- (BOOL)verifyTransaction:(SKPaymentTransaction*)transaction
                inReceipt:(RMAppReceipt*)receipt
				  success:(void (^)(void))successBlock
                           failure:(void (^)(NSError *error))failureBlock
{
    const BOOL receiptVerified = [self verifyAppReceipt:receipt error:NULL];
    if (!receiptVerified)
    {
        [self failWithBlock:failureBlock message:NSLocalizedStringFromTable(@"The app receipt failed verification", @"RMStore", nil)];
        return NO;
    }
    SKPayment *payment = transaction.payment;
    const BOOL transactionVerified = [receipt containsInAppPurchaseOfProductIdentifier:payment.productIdentifier];
    if (!transactionVerified)
    {
        [self failWithBlock:failureBlock message:NSLocalizedStringFromTable(@"The app receipt does not contain the given product", @"RMStore", nil)];
        return NO;
    }
    if (successBlock)
    {
        successBlock();
    }
    return YES;
}

- (void)failWithBlock:(void (^)(NSError *error))failureBlock message:(NSString*)message
{
    NSError *error = [NSError errorWithDomain:RMStoreErrorDomain code:0 userInfo:@{NSLocalizedDescriptionKey : message}];
    [self failWithBlock:failureBlock error:error];
}

- (void)failWithBlock:(void (^)(NSError *error))failureBlock error:(NSError*)error
{
    if (failureBlock)
    {
        failureBlock(error);
    }
}

@end
