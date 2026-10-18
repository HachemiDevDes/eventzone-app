import 'package:flutter_test/flutter_test.dart';
import 'package:eventzone_app/services/business_card_scanner_service.dart';
import 'package:eventzone_app/screens/review_contact_screen.dart';

void main() {
  group('BusinessCardScannerService Normalization Tests', () {
    test('Email normalization cleans whitespace, commas, brackets, and trailing dots', () {
      expect(BusinessCardScannerService.normalizeEmail(null), isNull);
      expect(BusinessCardScannerService.normalizeEmail(''), isNull);
      expect(BusinessCardScannerService.normalizeEmail('   '), isNull);
      expect(BusinessCardScannerService.normalizeEmail('user@domain.com'), 'user@domain.com');
      expect(BusinessCardScannerService.normalizeEmail('user @ domain.com'), 'user@domain.com');
      expect(BusinessCardScannerService.normalizeEmail('user@domain,com'), 'user@domain.com');
      expect(BusinessCardScannerService.normalizeEmail('alex.oneill@cloud-0ne,io.'), 'alex.oneill@cloud-0ne.io');
      expect(BusinessCardScannerService.normalizeEmail('<user@domain.com>'), 'user@domain.com');
      expect(BusinessCardScannerService.normalizeEmail('<user@domain.com.>'), 'user@domain.com');
      expect(BusinessCardScannerService.normalizeEmail('mailto:user@domain.com'), 'user@domain.com');
      expect(BusinessCardScannerService.normalizeEmail('user@domain..com'), 'user@domain.com');
    });

    test('Phone normalization preserves leading +, strips multilingual labels, and fixes brackets', () {
      expect(BusinessCardScannerService.normalizePhone(null), isNull);
      expect(BusinessCardScannerService.normalizePhone(''), isNull);
      expect(BusinessCardScannerService.normalizePhone('   '), isNull);
      expect(BusinessCardScannerService.normalizePhone('Tel: +213 555 12 34 56'), '+213 555 12 34 56');
      expect(BusinessCardScannerService.normalizePhone('Tél: +213 555 12 34 56'), '+213 555 12 34 56');
      expect(BusinessCardScannerService.normalizePhone('GSM: +213 555 12 34 56'), '+213 555 12 34 56');
      expect(BusinessCardScannerService.normalizePhone('Port: +213 555 12 34 56'), '+213 555 12 34 56');
      expect(BusinessCardScannerService.normalizePhone('Phone/Fax: +33 1 42 68 55 00'), '+33 1 42 68 55 00');
      expect(BusinessCardScannerService.normalizePhone('(+213) 555 12 34 56'), '+213 555 12 34 56');
      expect(BusinessCardScannerService.normalizePhone('+ 213 555 12 34 56'), '+213 555 12 34 56');
      expect(BusinessCardScannerService.normalizePhone('Tel: +1 (555) 019-2834'), '+1 (555) 019-2834');
      expect(BusinessCardScannerService.normalizePhone('0555.12.34.56'), '0555.12.34.56');
      expect(BusinessCardScannerService.normalizePhone('0555-12-34-56.'), '0555-12-34-56');
    });

    test('Website normalization strips labels, spaces, commas, and trailing slashes/dots', () {
      expect(BusinessCardScannerService.normalizeWebsite(null), isNull);
      expect(BusinessCardScannerService.normalizeWebsite(''), isNull);
      expect(BusinessCardScannerService.normalizeWebsite('   '), isNull);
      expect(BusinessCardScannerService.normalizeWebsite('www.eventzone.dz'), 'www.eventzone.dz');
      expect(BusinessCardScannerService.normalizeWebsite('www.eventzone.dz/'), 'www.eventzone.dz');
      expect(BusinessCardScannerService.normalizeWebsite('Web: www.eventzone.dz'), 'www.eventzone.dz');
      expect(BusinessCardScannerService.normalizeWebsite('Website: www.eventzone.dz/'), 'www.eventzone.dz');
      expect(BusinessCardScannerService.normalizeWebsite('Site web: www.eventzone.dz'), 'www.eventzone.dz');
      expect(BusinessCardScannerService.normalizeWebsite('www . eventzone . dz'), 'www.eventzone.dz');
      expect(BusinessCardScannerService.normalizeWebsite('www,eventzone,dz'), 'www.eventzone.dz');
      expect(BusinessCardScannerService.normalizeWebsite('https://eventzone.dz/.'), 'https://eventzone.dz');
      expect(BusinessCardScannerService.normalizeWebsite('<www.eventzone.dz>'), 'www.eventzone.dz');
    });

    test('ScannedBusinessCard.fromJson cleans all fields simultaneously', () {
      final json = {
        'name': '  Sarah Connor  ',
        'title': 'Lead Architect ',
        'company': ' Cyberdyne Systems ',
        'department': 'R&D',
        'email': '  sarah . connor @ cyberdyne , com . ',
        'phone': ' Tél: +213 555 019 2834 ',
        'website': ' Web: www . cyberdyne , com / ',
        'address': ' 12 Cyber St ',
        'notes': ' Founder ',
        'is_business_card': true,
      };

      final card = ScannedBusinessCard.fromJson(json);

      expect(card.name, 'Sarah Connor');
      expect(card.title, 'Lead Architect');
      expect(card.company, 'Cyberdyne Systems');
      expect(card.department, 'R&D');
      expect(card.email, 'sarah.connor@cyberdyne.com');
      expect(card.phone, '+213 555 019 2834');
      expect(card.website, 'www.cyberdyne.com');
      expect(card.address, '12 Cyber St');
      expect(card.notes, 'Founder');
      expect(card.isBusinessCard, true);
    });

    test('ScannedBusinessCard.fromJson safely parses null and missing optional fields', () {
      final json = {
        'name': 'John Doe',
        'title': 'Consultant',
        'company': 'Acme Corp',
        'department': null,
        'email': null,
        'phone': null,
        'website': null,
        'address': null,
        'notes': null,
        'is_business_card': true,
      };

      final card = ScannedBusinessCard.fromJson(json);

      expect(card.name, 'John Doe');
      expect(card.title, 'Consultant');
      expect(card.company, 'Acme Corp');
      expect(card.department, isNull);
      expect(card.email, '');
      expect(card.phone, '');
      expect(card.website, isNull);
      expect(card.address, isNull);
      expect(card.notes, isNull);
      expect(card.isBusinessCard, true);
    });
  });

  group('ReviewContactScreen Validator Tests', () {
    test('Email validator accepts valid emails and null/empty, rejects malformed', () {
      expect(ReviewContactScreen.validateEmail(null), isNull);
      expect(ReviewContactScreen.validateEmail(''), isNull);
      expect(ReviewContactScreen.validateEmail('   '), isNull);
      expect(ReviewContactScreen.validateEmail('sarah.connor@cyberdyne.com'), isNull);
      expect(ReviewContactScreen.validateEmail('sarah+tag@cyberdyne-0ne.io'), isNull);
      expect(ReviewContactScreen.validateEmail('notanemail'), isNotNull);
      expect(ReviewContactScreen.validateEmail('name@'), isNotNull);
      expect(ReviewContactScreen.validateEmail('name@domain'), isNotNull);
      expect(ReviewContactScreen.validateEmail('name @domain.com'), isNotNull);
    });

    test('Phone validator accepts valid numbers and null/empty, rejects under 6 digits', () {
      expect(ReviewContactScreen.validatePhone(null), isNull);
      expect(ReviewContactScreen.validatePhone(''), isNull);
      expect(ReviewContactScreen.validatePhone('+213 555 019 283'), isNull);
      expect(ReviewContactScreen.validatePhone('0555 12 34 56'), isNull);
      expect(ReviewContactScreen.validatePhone('+1 (555) 019-2834'), isNull);
      expect(ReviewContactScreen.validatePhone('12345'), isNotNull);
      expect(ReviewContactScreen.validatePhone('abc'), isNotNull);
    });

    test('Website validator accepts domains and URLs, rejects invalid strings', () {
      expect(ReviewContactScreen.validateWebsite(null), isNull);
      expect(ReviewContactScreen.validateWebsite(''), isNull);
      expect(ReviewContactScreen.validateWebsite('cyberdyne.com'), isNull);
      expect(ReviewContactScreen.validateWebsite('www.cyberdyne.io'), isNull);
      expect(ReviewContactScreen.validateWebsite('https://eventzone.dz'), isNull);
      expect(ReviewContactScreen.validateWebsite('http://eventzone.dz/contact'), isNull);
      expect(ReviewContactScreen.validateWebsite('invalid-site'), isNotNull);
      expect(ReviewContactScreen.validateWebsite('http://'), isNotNull);
    });
  });
}
