import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_libphonenumber/src/country_data.dart';
import 'package:flutter_libphonenumber/src/format_phone_result.dart';
import 'package:flutter_libphonenumber/src/input_formatter/phone_mask.dart';
import 'package:flutter_libphonenumber/src/phone_number_format.dart';
import 'package:flutter_libphonenumber/src/phone_number_type.dart';

export 'package:flutter_libphonenumber/src/country_data.dart';
export 'package:flutter_libphonenumber/src/format_phone_result.dart';
export 'package:flutter_libphonenumber/src/input_formatter/input_formatter.dart';
export 'package:flutter_libphonenumber/src/phone_number_format.dart';
export 'package:flutter_libphonenumber/src/phone_number_type.dart';

class FlutterLibphonenumber {
  FlutterLibphonenumber._internal();
  factory FlutterLibphonenumber() => _instance;
  static final FlutterLibphonenumber _instance =
      FlutterLibphonenumber._internal();

  /// Method channel
  final _channel = const MethodChannel('flutter_libphonenumber');

  /// Must call this before anything else so the countries data is populated.
  ///
  /// Optionally provide a map of overrides where the key is the country code
  /// (ex: `GB` or `US`) and the value is a `CountryWithPhoneCode` object
  /// that should replace the data pulled from libphonenumber. This is useful
  /// if you want to customize the mask data for a given country.
  Future<void> init({
    Map<String, CountryWithPhoneCode> overrides = const {},
  }) async {
    return CountryManager().loadCountries(overrides: overrides);
  }

  /// Return all available regions with their country code, phone code, and formatted
  /// example number as a mask. Useful to later format phone numbers using a mask.
  ///
  /// The response will be a [CountryWithPhoneCode]:
  ///
  /// There are some performance considerations for this so you might want to cache the
  /// result and re-use it elsewhere. There's a lot of data to iterate over.
  Future<Map<String, CountryWithPhoneCode>> getAllSupportedRegions() async {
    /// Here is what will return from the platform call:
    /// ```
    /// {
    ///   "UK": {
    ///     "phoneCode": 44,
    ///     "exampleNumberMobileNational": "07400 123456",
    ///     "exampleNumberFixedLineNational": "0121 234 5678",
    ///     "phoneMaskMobileNational": "+00 00000 000000",
    ///     "phoneMaskFixedLineNational": "+00 0000 000 0000",
    ///     "exampleNumberMobileInternational": "+44 7400 123456",
    ///     "exampleNumberFixedLineInternational": "+44 121 234 5678",
    ///     "phoneMaskMobileInternational": "+00 +00 0000 000000",
    ///     "phoneMaskFixedLineInternational": "+00 +00 000 000 0000",
    ///     "countryName": "United Kingdom"
    ///   }
    /// }
    /// ```
    final result = await _channel
            .invokeMapMethod<String, dynamic>('get_all_supported_regions') ??
        {};

    final returnMap = <String, CountryWithPhoneCode>{};
    result.forEach(
      (k, v) => returnMap[k] = CountryWithPhoneCode(
        countryName: v['countryName'] ?? '',
        phoneCode: v['phoneCode'] ?? '',
        countryCode: k,
        exampleNumberMobileNational: v['exampleNumberMobileNational'] ?? '',
        exampleNumberFixedLineNational:
            v['exampleNumberFixedLineNational'] ?? '',
        phoneMaskMobileNational: v['phoneMaskMobileNational'] ?? '',
        phoneMaskFixedLineNational: v['phoneMaskFixedLineNational'] ?? '',
        exampleNumberMobileInternational: k == 'EE'
            ? [v['exampleNumberMobileInternational'] ?? '', '+372 512 3456']
            : [v['exampleNumberMobileInternational'] ?? ''],
        exampleNumberFixedLineInternational:
            v['exampleNumberFixedLineInternational'] ?? '',
        phoneMaskMobileInternational: v['phoneMaskMobileInternational'] ?? '',
        phoneMaskFixedLineInternational:
            v['phoneMaskFixedLineInternational'] ?? '',
      ),
    );
    return returnMap;
  }

  /// Formats a phone number using platform libphonenumber. Will return the parsed number.
  ///
  /// Example response:
  /// ```
  /// {
  ///   formatted: "1 (414) 444-4444",
  /// }
  /// ```
  Future<Map<String, String>> format(String phone, String region) async {
    return await _channel.invokeMapMethod<String, String>('format', {
          'phone': phone,
          'region': region,
        }) ??
        <String, String>{};
  }

  /// Parse a single string and return a map in the format below. Throws an error if the
  /// number is not a valid e164 phone number.
  ///
  /// Given a passed [phone] like '+4930123123123', the response will be:
  /// ```
  /// {
  ///   country_code: 49,
  ///   e164: '+4930123123123',
  ///   national: '030 123 123 123',
  ///   type: 'mobile',
  ///   international: '+49 30 123 123 123',
  ///   national_number: '030123123123',
  /// }
  /// ```
  Future<Map<String, dynamic>> parse(String phone, {String? region}) async {
    return await _channel.invokeMapMethod<String, dynamic>('parse', {
          'phone': phone,
          'region': region,
        }) ??
        <String, dynamic>{};
  }

  /// Given a phone number, format it automatically using the masks we have from
  /// libphonenumber's example numbers. Optionally override the country (instead
  /// of auto-detecting), the number type, format.
  ///
  /// Use [removeCountryCodeFromResult] to strip the country code from the result
  /// and set [inputContainsCountryCode] based on if the input contains a country
  /// code or not so the correct mask can be used.
  String formatNumberSync(
    String number, {
    CountryWithPhoneCode? country,
    PhoneNumberType phoneNumberType = PhoneNumberType.mobile,
    PhoneNumberFormat phoneNumberFormat = PhoneNumberFormat.international,
    bool removeCountryCodeFromResult = false,
    bool inputContainsCountryCode = true,
  }) {
    final guessedCountry =
        country ?? CountryWithPhoneCode.getCountryDataByPhone(number);

    if (guessedCountry == null) {
      return number;
    }

    var formatResult = PhoneMask(
      guessedCountry.getPhoneMask(
        format: phoneNumberFormat,
        type: phoneNumberType,
        removeCountryCodeFromMask: !inputContainsCountryCode,
      ),
    ).apply(number);

    /// Remove the country code from the result if the user set removeCountryCodeFromResult=true.
    /// Take a substring of the phone code length + 2 to account for leading `+` and space between
    /// country code and the number.
    if (removeCountryCodeFromResult && inputContainsCountryCode) {
      formatResult =
          formatResult.substring(guessedCountry.phoneCode.length + 2);
    }

    return formatResult;
  }

  /// Asynchronously formats a number, returning the e164 and the number's requested format
  /// result by specifying a [PhoneNumberType] and [PhoneNumberFormat].
  ///
  /// If the number is invalid or cannot be parsed, it will return a null result.
  Future<FormatPhoneResult?> getFormattedParseResult(
    String phoneNumber,
    CountryWithPhoneCode country, {
    PhoneNumberType phoneNumberType = PhoneNumberType.mobile,
    PhoneNumberFormat phoneNumberFormat = PhoneNumberFormat.international,
  }) async {
    try {
      /// Try to parse the number and get our result
      final res = await parse(
        phoneNumber,
        region: country.countryCode,
      );

      late final String formattedNumber;
      if (phoneNumberFormat == PhoneNumberFormat.international) {
        formattedNumber = res['international'] ?? '';
      } else if (phoneNumberFormat == PhoneNumberFormat.national) {
        formattedNumber = res['national'] ?? '';
      } else {
        /// Should never happen
        formattedNumber = '';
      }

      /// Now construct the return value based on the requested format/type.
      return FormatPhoneResult(
        e164: res['e164'] ?? '',
        formattedNumber: formattedNumber,
      );
    } catch (e) {
      // print(e);
    }

    return null;
  }
}
