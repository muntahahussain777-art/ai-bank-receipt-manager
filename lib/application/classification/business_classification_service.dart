import 'package:ai_bank_receipt_manager/data/models/db_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/office_account_models.dart';
import 'package:ai_bank_receipt_manager/data/models/office_enums.dart';
import 'package:ai_bank_receipt_manager/data/models/persistence_models.dart';
import 'package:ai_bank_receipt_manager/data/utils/alias_normalize.dart';

class AliasHit {
  const AliasHit({
    required this.entityId,
    required this.label,
    required this.matchedAlias,
    required this.exact,
  });

  final String entityId;
  final String label;
  final String matchedAlias;
  final bool exact;
}

class ClassificationInput {
  const ClassificationInput({
    this.bankSenderName,
    this.bankReceiverName,
    this.adminMessage,
    this.whatsappSender,
    this.bankDirectionHint,
  });

  final String? bankSenderName;
  final String? bankReceiverName;
  final String? adminMessage;
  final String? whatsappSender;

  /// Optional hint from the bank receipt itself (credit/debit), not office flow.
  final DbReceiptType? bankDirectionHint;
}

class ClassificationResult {
  const ClassificationResult({
    required this.proposedReceiptType,
    required this.needsReview,
    required this.possibleInternalTransfer,
    required this.reasons,
    required this.officeAccountSuggestions,
    required this.customerSuggestions,
    required this.dealerSuggestions,
    this.officeAccountId,
    this.customerId,
    this.dealerId,
  });

  final DbReceiptType proposedReceiptType;
  final bool needsReview;
  final bool possibleInternalTransfer;
  final List<String> reasons;
  final List<AliasHit> officeAccountSuggestions;
  final List<AliasHit> customerSuggestions;
  final List<AliasHit> dealerSuggestions;
  final String? officeAccountId;
  final String? customerId;
  final String? dealerId;
}

/// Applies Customer -> Office (incoming) and Office -> Dealer (outgoing)
/// for ANY active office account. Never auto-links ambiguous aliases.
class BusinessClassificationService {
  ClassificationResult classify({
    required ClassificationInput input,
    required List<OfficeAccountRecord> accounts,
    required Map<String, List<OfficeAccountAliasRecord>> accountAliases,
    required List<CustomerRecord> customers,
    required Map<String, List<PartyAliasRecord>> customerAliases,
    required List<DealerRecord> dealers,
    required Map<String, List<PartyAliasRecord>> dealerAliases,
  }) {
    final activeAccounts = [
      for (final account in accounts)
        if (account.isSelectableForNewEntries) account,
    ];

    final senderHits = _matchAccounts(
      input.bankSenderName,
      activeAccounts,
      accountAliases,
    );
    final receiverHits = _matchAccounts(
      input.bankReceiverName,
      activeAccounts,
      accountAliases,
    );
    final adminAccountHits = _matchAccountsInText(
      input.adminMessage,
      activeAccounts,
      accountAliases,
    );
    final customerHits = [
      ..._matchCustomers(input.bankSenderName, customers, customerAliases),
      ..._matchCustomers(input.adminMessage, customers, customerAliases),
    ];
    final dealerHits = [
      ..._matchDealers(input.bankReceiverName, dealers, dealerAliases),
      ..._matchDealers(input.adminMessage, dealers, dealerAliases),
    ];

    final reasons = <String>[];
    var needsReview = false;
    var internal = false;
    DbReceiptType proposed = DbReceiptType.unknown;
    String? officeId;
    String? customerId;
    String? dealerId;

    final senderOffice = _decisiveHits(senderHits);
    final receiverOffice = _decisiveHits(receiverHits);

    if (senderOffice.length == 1 && receiverOffice.length == 1) {
      if (senderOffice.first.entityId != receiverOffice.first.entityId) {
        internal = true;
        needsReview = true;
        reasons.add(
          'Sender and receiver both match office accounts (possible internal transfer).',
        );
      }
    }

    // Customer -> Office = incoming when receiver is an office account.
    if (receiverOffice.length == 1 && senderOffice.isEmpty) {
      officeId = receiverOffice.first.entityId;
      proposed = DbReceiptType.received;
      reasons.add(
        'Bank receiver matched office account ${receiverOffice.first.label}; '
        'proposed incoming (customer to office).',
      );
      if (!receiverOffice.first.exact) {
        needsReview = true;
        reasons.add('Receiver match is similar, not exact; confirm before linking.');
      }
    } else if (senderOffice.length == 1 && receiverOffice.isEmpty) {
      officeId = senderOffice.first.entityId;
      proposed = DbReceiptType.sent;
      reasons.add(
        'Bank sender matched office account ${senderOffice.first.label}; '
        'proposed outgoing (office to dealer).',
      );
      if (!senderOffice.first.exact) {
        needsReview = true;
        reasons.add('Sender match is similar, not exact; confirm before linking.');
      }
    } else if (receiverOffice.length > 1 || senderOffice.length > 1) {
      needsReview = true;
      reasons.add('Several office accounts matched the same bank name.');
    } else if (senderOffice.isEmpty && receiverOffice.isEmpty) {
      needsReview = true;
      reasons.add('No office account matched the bank sender/receiver.');
    }

    final uniqueCustomers = _uniqueHits(customerHits);
    final uniqueDealers = _uniqueHits(dealerHits);
    if (uniqueCustomers.length == 1 && proposed == DbReceiptType.received) {
      customerId = uniqueCustomers.first.entityId;
    } else if (uniqueCustomers.length > 1) {
      needsReview = true;
      reasons.add('Several customers matched; confirmation required.');
    }
    if (uniqueDealers.length == 1 && proposed == DbReceiptType.sent) {
      dealerId = uniqueDealers.first.entityId;
    } else if (uniqueDealers.length > 1) {
      needsReview = true;
      reasons.add('Several dealers matched; confirmation required.');
    }

    final adminOffice = _decisiveHits(adminAccountHits);
    if (adminOffice.length == 1) {
      if (officeId == null) {
        officeId = adminOffice.first.entityId;
        reasons.add(
          'Admin message suggested office account ${adminOffice.first.label} '
          '(not treated as bank-direction proof).',
        );
        needsReview = true;
      } else if (officeId != adminOffice.first.entityId) {
        needsReview = true;
        reasons.add(
          'Admin message office account conflicts with bank-side match.',
        );
      }
    } else if (adminOffice.length > 1) {
      needsReview = true;
      reasons.add('Admin message matched several office accounts.');
    }

    if (input.bankDirectionHint != null &&
        input.bankDirectionHint != DbReceiptType.unknown &&
        proposed != DbReceiptType.unknown &&
        input.bankDirectionHint != proposed) {
      needsReview = true;
      reasons.add(
        'Bank receipt direction hint conflicts with proposed office classification.',
      );
    }

    if (officeId == null && !internal) {
      needsReview = true;
    }

    return ClassificationResult(
      proposedReceiptType: proposed,
      needsReview: needsReview,
      possibleInternalTransfer: internal,
      reasons: reasons,
      officeAccountSuggestions: [
        ...senderHits,
        ...receiverHits,
        ...adminAccountHits,
      ],
      customerSuggestions: uniqueCustomers,
      dealerSuggestions: uniqueDealers,
      officeAccountId: officeId,
      customerId: customerId,
      dealerId: dealerId,
    );
  }

  /// Prefer exact unique hits; otherwise a single similar entity may suggest.
  List<AliasHit> _decisiveHits(List<AliasHit> hits) {
    final uniqueExact = _uniqueHits([
      for (final hit in hits)
        if (hit.exact) hit,
    ]);
    if (uniqueExact.isNotEmpty) {
      return uniqueExact;
    }
    return _uniqueHits(hits);
  }

  List<AliasHit> _matchAccounts(
    String? raw,
    List<OfficeAccountRecord> accounts,
    Map<String, List<OfficeAccountAliasRecord>> aliases,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final hits = <AliasHit>[];
    for (final account in accounts) {
      hits.addAll(
        _hitsFor(
          raw: raw,
          entityId: account.id,
          label: account.displayName,
          names: [
            account.displayName,
            for (final alias in aliases[account.id] ?? const [])
              if (alias.approvalStatus == AliasApprovalStatus.approved)
                alias.aliasName,
          ],
        ),
      );
    }
    return hits;
  }

  List<AliasHit> _matchAccountsInText(
    String? text,
    List<OfficeAccountRecord> accounts,
    Map<String, List<OfficeAccountAliasRecord>> aliases,
  ) {
    if (text == null || text.trim().isEmpty) {
      return const [];
    }
    final hits = <AliasHit>[];
    for (final account in accounts) {
      final names = [
        account.displayName,
        for (final alias in aliases[account.id] ?? const [])
          if (alias.approvalStatus == AliasApprovalStatus.approved)
            alias.aliasName,
      ];
      for (final name in names) {
        if (text.toLowerCase().contains(name.toLowerCase()) ||
            aliasesLookSimilar(text, name)) {
          hits.add(
            AliasHit(
              entityId: account.id,
              label: account.displayName,
              matchedAlias: name,
              exact:
                  text.toLowerCase().contains(name.toLowerCase()) ||
                  normalizeAlias(text) == normalizeAlias(name),
            ),
          );
        }
      }
    }
    return hits;
  }

  List<AliasHit> _matchCustomers(
    String? raw,
    List<CustomerRecord> customers,
    Map<String, List<PartyAliasRecord>> aliases,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final hits = <AliasHit>[];
    for (final customer in customers) {
      if (customer.deletedAt != null) {
        continue;
      }
      hits.addAll(
        _hitsFor(
          raw: raw,
          entityId: customer.id,
          label: customer.name,
          names: [
            customer.name,
            for (final alias in aliases[customer.id] ?? const [])
              if (alias.approvalStatus == AliasApprovalStatus.approved)
                alias.aliasName,
          ],
        ),
      );
    }
    return hits;
  }

  List<AliasHit> _matchDealers(
    String? raw,
    List<DealerRecord> dealers,
    Map<String, List<PartyAliasRecord>> aliases,
  ) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final hits = <AliasHit>[];
    for (final dealer in dealers) {
      if (dealer.deletedAt != null) {
        continue;
      }
      hits.addAll(
        _hitsFor(
          raw: raw,
          entityId: dealer.id,
          label: dealer.name,
          names: [
            dealer.name,
            for (final alias in aliases[dealer.id] ?? const [])
              if (alias.approvalStatus == AliasApprovalStatus.approved)
                alias.aliasName,
          ],
        ),
      );
    }
    return hits;
  }

  List<AliasHit> _hitsFor({
    required String raw,
    required String entityId,
    required String label,
    required List<String> names,
  }) {
    final hits = <AliasHit>[];
    for (final name in names) {
      final exact = normalizeAlias(raw) == normalizeAlias(name);
      final similar = aliasesLookSimilar(raw, name);
      if (exact || similar) {
        hits.add(
          AliasHit(
            entityId: entityId,
            label: label,
            matchedAlias: name,
            exact: exact,
          ),
        );
      }
    }
    return hits;
  }

  List<AliasHit> _uniqueHits(List<AliasHit> hits) {
    final byId = <String, AliasHit>{};
    for (final hit in hits) {
      final current = byId[hit.entityId];
      if (current == null || (!current.exact && hit.exact)) {
        byId[hit.entityId] = hit;
      }
    }
    return byId.values.toList();
  }
}
