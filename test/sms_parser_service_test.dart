import 'package:finnance_app/models/sms_message_record.dart';
import 'package:finnance_app/models/transaction_models.dart';
import 'package:finnance_app/services/sms_parser_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SmsSenderCatalog', () {
    test('normalizes operator prefixes and DLT suffixes', () {
      const catalog = SmsSenderCatalog();

      expect(catalog.normalize('VM-HDFCBK-T'), 'HDFCBK');
      expect(catalog.normalize('AX-ICICIC-P'), 'ICICIC');
      expect(catalog.normalize('SBIUPI'), 'SBIUPI');
    });
  });

  group('DefaultSmsParserService', () {
    final parser = DefaultSmsParserService();

    test('parses UPI debit transaction alerts', () {
      final transaction = parser.parse(
        const SmsMessageRecord(
          id: 'sms-1',
          sender: 'VM-HDFCBK-T',
          body:
              'Rs.1,234.50 debited from A/c XX1234 via UPI to Zomato on 19-05-26. UPI Ref 123456.',
          timestampMillis: 1779177600000,
        ),
      );

      expect(transaction, isNotNull);
      expect(transaction!.sourceSmsId, startsWith('sms_'));
      expect(transaction.normalizedSender, 'HDFCBK');
      expect(transaction.amountPaise, 123450);
      expect(transaction.direction, TransactionDirection.expense);
      expect(transaction.instrument, TransactionInstrument.upi);
      expect(transaction.accountOrCardHint, '1234');
      expect(transaction.merchantOrPayee, 'Zomato');
    });

    test('parses credit card spend without treating credit card as income', () {
      final transaction = parser.parse(
        const SmsMessageRecord(
          id: 'sms-2',
          sender: 'AX-ICICIC-P',
          body:
              'Your ICICI Bank Credit Card ending 4321 was used for INR 2,499.00 at Amazon.',
          timestampMillis: 1779177600000,
        ),
      );

      expect(transaction, isNotNull);
      expect(transaction!.amountPaise, 249900);
      expect(transaction.instrument, TransactionInstrument.creditCard);
      expect(transaction.accountOrCardHint, '4321');
      expect(transaction.merchantOrPayee, 'Amazon');
    });

    test('ignores credited, refund, and reversal messages', () {
      expect(
        parser.parse(
          const SmsMessageRecord(
            id: 'sms-3',
            sender: 'AXISBK',
            body: 'Rs.500 credited to your A/c XX1234 on 19-05-26.',
            timestampMillis: 1779177600000,
          ),
        ),
        isNull,
      );
      expect(
        parser.parse(
          const SmsMessageRecord(
            id: 'sms-4',
            sender: 'HDFCBK',
            body: 'Refund of INR 299.00 has been processed for your card.',
            timestampMillis: 1779177600000,
          ),
        ),
        isNull,
      );
      expect(
        parser.parse(
          const SmsMessageRecord(
            id: 'sms-5',
            sender: 'ICICIB',
            body: 'Reversal for Rs.700 transaction has been completed.',
            timestampMillis: 1779177600000,
          ),
        ),
        isNull,
      );
    });

    test('ignores OTP and promotional messages with amounts', () {
      expect(
        parser.parse(
          const SmsMessageRecord(
            id: 'sms-6',
            sender: 'HDFCBK',
            body: 'OTP 123456 for purchase of Rs.1000. Do not share it.',
            timestampMillis: 1779177600000,
          ),
        ),
        isNull,
      );
      expect(
        parser.parse(
          const SmsMessageRecord(
            id: 'sms-7',
            sender: 'KOTAKB',
            body: 'Pre-approved loan offer up to Rs.500000. Apply now.',
            timestampMillis: 1779177600000,
          ),
        ),
        isNull,
      );
    });

    test('prefers transaction amount over available balance amount', () {
      final transaction = parser.parse(
        const SmsMessageRecord(
          id: 'sms-8',
          sender: 'SBIUPI',
          body:
              'A/c XX9988 debited by INR 450.00 for UPI payment to Tea Shop. Available balance INR 10,000.00.',
          timestampMillis: 1779177600000,
        ),
      );

      expect(transaction, isNotNull);
      expect(transaction!.amountPaise, 45000);
      expect(transaction.instrument, TransactionInstrument.upi);
    });
  });
}
