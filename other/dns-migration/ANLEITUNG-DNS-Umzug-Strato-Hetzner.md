# DNS-Umzug von Strato zu Hetzner

**Ziel:** Die DNS-Zone von `example.de` (Hauptdomain plus ca. 30 Subdomains) wird künftig bei Hetzner verwaltet.
**Grundsatz:** Zuerst ziehen nur die Nameserver um, die Domain bleibt bei Strato registriert. So lässt sich alles mit einer Einstellung zurückdrehen. Den Domain-Transfer macht ihr später und getrennt davon, falls überhaupt.

> Mit „Vermutung" markierte Punkte vorher bei Strato bzw. Hetzner bestätigen.

---

## 1. Vorab klären (1–2 Wochen vorher)

- [ ] **Strato-Postfächer:** Bei Strato nachfragen, ob die Postfächer mit externen Nameservern uneingeschränkt weiterlaufen und welche Einträge nötig sind (MX, SPF, DKIM, Autodiscover). *Vermutung: ja, wenn die Einträge stimmen.*
- [ ] **DNSSEC:** Ist es bei Strato aktiv? Dann **vor** dem Nameserver-Wechsel abschalten und 2 Tage warten. Sonst ist die Domain nach dem Wechsel nicht erreichbar.
- [ ] **Hetzner-Projekt:** Die DNS-Zone in ein **eigenes Projekt** legen. API-Tokens gelten je Projekt, ein DNS-Token soll keine Server steuern können.
- [ ] **Werkzeuge:** Prüfen, ob eingesetzte Werkzeuge mit Hetzner-DNS-API (Zertifikate, Skripte) die aktuelle Hetzner-API unterstützen. *Vermutung: Hetzner stellt die DNS-Verwaltung gerade auf die Cloud Console um.* Die deSEC-CNAME-Lösung ist davon nicht betroffen.

## 2. Bestand aufnehmen

1. Die aktuellen Nameserver notieren:
   ```
   dig +short NS example.de
   ```
2. Bei Strato **alle** Einträge abschreiben (Strato bietet keinen Zonen-Export) und in `zone-bestand.txt` festhalten. Nicht vergessen:
   - Hauptdomain: A, AAAA, MX, TXT (SPF, DMARC, Verifizierungen für Microsoft, Google o. Ä.), CAA
   - jede Subdomain: A, AAAA, CNAME
   - `_acme-challenge.*` → deSEC (CNAMEs für die Zertifikate)
   - DKIM-Schlüssel (`*._domainkey`), `_dmarc`, `autodiscover`, `_autodiscover._tcp` (SRV)
   - sonstige SRV-Einträge (`_sip`, `_caldav` usw.)
   - Einträge, die Strato automatisch setzt und die in der Oberfläche evtl. nicht sichtbar sind. Diese per `dig` gegenprüfen (Liste in Schritt 4).
3. Eine Namensliste `namen.txt` anlegen, ein Name pro Zeile, z. B.:
   ```
   example.de
   www.example.de
   cloud.example.de
   _acme-challenge.cloud.example.de
   _dmarc.example.de
   default._domainkey.example.de
   ```

## 3. TTL senken (mind. 2 Tage vorher)

Bei Strato die TTL aller Einträge auf **300 s** setzen, soweit möglich. Danach mindestens die alte TTL abwarten (meist 1 Tag).

## 4. Zone bei Hetzner nachbauen und vergleichen

1. Zone `example.de` in der Hetzner-Konsole anlegen und alle Einträge übertragen, ebenfalls mit TTL 300.
2. Die Hetzner-Nameserver der Zone notieren (stehen in der Konsole).
3. **Vergleich** beider Nameserver. Das Skript zeigt nur Abweichungen:
   ```bash
   #!/bin/bash
   # Aufruf: ./dns-vergleich.sh <strato-ns> <hetzner-ns> namen.txt
   ALT=$1; NEU=$2; LISTE=$3
   for n in $(cat "$LISTE"); do
     for t in A AAAA CNAME MX TXT SRV CAA NS; do
       a=$(dig +short @"$ALT" "$n" "$t" | sort)
       b=$(dig +short @"$NEU" "$n" "$t" | sort)
       [ "$a" != "$b" ] && printf '%-40s %-5s\n  Strato:  %s\n  Hetzner: %s\n' "$n" "$t" "$a" "$b"
     done
   done
   echo "Vergleich fertig."
   ```
   Abweichend dürfen nur die NS-Einträge der Hauptdomain sein. Alles andere so lange korrigieren, bis das Skript nichts mehr meldet.

## 5. Umschalten

1. Zeitpunkt mit wenig Betrieb wählen. Kollegen informieren, dass es kurz zu Mailverzögerungen kommen kann.
2. Bei Strato in der Domainverwaltung die Nameserver auf die Hetzner-Nameserver umstellen. *Vermutung: Menüpunkt „Nameserver" bzw. „Externe Nameserver" je Domain.*
3. Die Umstellung an der .de-Registry prüfen, das kann von Minuten bis zu einigen Stunden dauern:
   ```
   dig +short NS example.de @a.nic.de
   ```

## 6. Nachkontrolle (am selben Tag und am Folgetag)

- [ ] Webseiten und alle Subdomains erreichbar
- [ ] Mail rein und raus, an Strato-Postfächer und von extern (z. B. Testmail von einem Freemail-Konto)
- [ ] SPF/DKIM/DMARC per Testmail prüfen (Mail-Header: `spf=pass`, `dkim=pass`)
- [ ] Ein Zertifikat testweise erneuern (DNS-Challenge über deSEC)
- [ ] Nach 1–2 Wochen ohne Auffälligkeiten die TTL auf 3600 s anheben
- [ ] Bei Bedarf DNSSEC bei Hetzner wieder einschalten (DS-Eintrag über Strato als Registrar)

## Rückweg

Bei Strato die Nameserver wieder auf die alten Werte (Schritt 2.1) stellen. Die alte Zone bei Strato **bis zum Abschluss nicht löschen.**
Wegen der TTL der NS-Einträge bei der .de-Registry (bis zu 1 Tag) wirkt der Rückweg nicht sofort.

## Später (optional): Domain-Transfer zu Hetzner

Erst, wenn das DNS einige Wochen stabil läuft **und** die Strato-Postfächer abgelöst sind. AuthInfo-Code bei Strato anfordern und den Transfer bei Hetzner beantragen. Die Nameserver bleiben dabei gleich.
