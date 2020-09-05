#!/bin/bash

### requisiti ###
# miller https://github.com/johnkerl/miller
# dateutils https://github.com/hroptatyr/dateutils
### requisiti ###

set -x

web="/home/ondata/domains/dev.ondata.it/public_html/projs/albopop/patti"

### anagrafica albo
titolo="AlboPOP del comune di Patti"
descrizione="L'albo pretorio POP è una versione dell'albo pretorio del tuo comune, che puoi seguire in modo più comodo."
nomecomune="patti"
webMaster="antonino.galante@gmail.com (Nino Galante)"
type="Comune"
municipality="Patti"
province="Messina"
region="Sicilia"
latitude="38.138226"
longitude="14.966359"
country="Italia"
name="Comune di Patti"
uid="istat:083066"
docs="http://albopop.it/comune/patti/"
selflink="http://dev.ondata.it/projs/albopop/patti/feed.xml"
### anagrafica albo

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$folder"/rawdata
mkdir -p "$folder"/processing

code=$(curl -s -L -o /dev/null -w "%{http_code}" 'http://www.comune.patti.me.it/index.php?option=com_albopretorio&id_Miky=_0')

if [ $code -eq 200 ]; then

  urlbase="http://www.comune.patti.me.it"

  # scarica lista allegati 2019-2020 e crea colonna in cui concatenarli per id
  curl -ksL "http://www.comune.patti.me.it/administrator/components/com_albopretorio/allegati/" |
    scrape -be "//table/tr[position() > 3]//a[contains(@href,'_2020-') or contains(@href,'_2019-')]" |
    xq -r '.html.body.a[]."@href"' |
    mlr --csv --implicit-csv-header put '$source="http://www.comune.patti.me.it/administrator/components/com_albopretorio/allegati/".$1' then nest --explode --values --across-fields --nested-fs "_" -f 1 then cut -f 1_2,source then nest --ivar " " -f source then label id >"$folder"/rawdata/listaAllegati.csv

  # scaricare in for loop tutto

  ## definizione xpath colonne
  NumeroAlboXP='//table[@class="adminlist"]/tbody/tr[td[contains(text(),"Numero Albo")]]/td[@class="Colonna_Dx"]'
  OggettoXP='//table[@class="adminlist"]/tbody/tr[td[contains(text(),"Oggetto")]]/td[@class="Colonna_Dx_Oggetto"]'
  daXP='//table[@class="adminlist"]/tbody/tr[td[contains(text(),"Periodo di")]]/td[@class="Colonna_Dx"]/span[1]'
  aXP='//table[@class="adminlist"]/tbody/tr[td[contains(text(),"Periodo di")]]/td[@class="Colonna_Dx"]/span[2]'
  hrefXP='//table[@class="adminlist"]/tbody/tr/td[@class="center"]/a/@onclick'
  EnteedUfficioXP='//table[@class="adminlist"]/tbody/tr[td[contains(text(),"Ente ed Ufficio")]]/td[@class="Colonna_Dx"]/span[2]'

  # crea lista pagina da scaricare
  curl -ksL "http://www.comune.patti.me.it/index.php?option=com_albopretorio&id_Miky=_0" |
    scrape -be '//div[@id="albopretorio"]/ul//a' |
    xq -r '.html.body.a[]."@href"' >"$folder"/rawdata/pagine.txt

  # cancella file html salvati
  rm "$folder"/rawdata/*.html

  # scarica pagina
  x=1
  while read p; do
    curl -kL "$urlbase""$p""&limit=50&limitstart=0" | perl -pe 's/\r\n/ /g' >"$folder"/rawdata/"$x".html
    x=$(($x + 1))
  done <"$folder"/rawdata/pagine.txt

  # cancella pagine senza elementi
  for i in "$folder"/rawdata/*.html; do
    if grep -q 'Nessun documento caricato' "$i"; then
      rm "$i"
    fi
  done

  # rimuovi CSV già creati
  rm "$folder"/processing/*.csv

  # estrai dai file HTML le info, inseriscile in dei file di testo e uniscili per sezione
  for i in "$folder"/rawdata/*.html; do
    #crea una variabile da usare per estrarre nome e estensione
    filename=$(basename "$i")
    #estrai estensione
    extension="${filename##*.}"
    #estrai nome file
    filename="${filename%.*}"
    scrape <"$i" -e ''"$NumeroAlboXP"'/text()' | tr '\t' '\n' | sed '$d' >"$folder"/processing/"$filename"_1.csv
    scrape <"$i" -e ''"$OggettoXP"'/text()' | tr '\t' '\n' | sed '$d' >"$folder"/processing/"$filename"_2.csv
    scrape <"$i" -e ''"$daXP"'/text()' | tr '\t' '\n' | sed '$d' >"$folder"/processing/"$filename"_3.csv
    scrape <"$i" -e ''"$hrefXP"'' | grep -oE '[0-9]{2,}' >"$folder"/processing/"$filename"_4.csv
    paste -d "\t" "$folder"/processing/"$filename"_*csv >"$folder"/processing/"$filename"_out.csv
  done

  # unisci tutti i CSV delle varie sezioni di albo
  mlr --icsvlite --ocsv --ifs tab --implicit-csv-header unsparsify then label id,des,data,href then clean-whitespace "$folder"/processing/*_out.csv >"$folder"/pubblicazioni.csv
  # fai JOIN con file allegati
  mlr --csv join -j href -l href -r id -f "$folder"/pubblicazioni.csv then unsparsify "$folder"/rawdata/listaAllegati.csv >"$folder"/rss.csv
  # rinomina colonna
  mlr -I --csv rename source,allegati "$folder"/rss.csv
  # rimuovi eventuali righe senza allegati
  mlr -I --csv filter -x '$allegati==""' "$folder"/rss.csv

  # converti date in formato RSS, converti caratteri non consentiti in XML e aggiungi la data nel titolo atto
  mlr -I --csv put '$RSSdata=system("dconv --from-locale it_IT -i \"%d %B %Y\" -f \"%a, %d %b %Y 02:00:00 +0200\" \"".$data."\"")' "$folder"/rss.csv
  mlr --c2t --quote-none sort -nr href \
    then put '$des=gsub($des,"<","&lt")' \
    then put '$des=gsub($des,">","&gt;")' \
    then put '$des=gsub($des,"&","&amp;")' \
    then put '$des=gsub($des,"'\''","&apos;")' \
    then put '$des=gsub($des,"\"","&quot;")' \
    then put '$guid=regextract($allegati,"http.{1,}-1[\.a-z]{1,}")' \
    then put '$des=$data." | ".$des' "$folder"/rss.csv |
    tail -n +2 >"$folder"/rss.tsv

  # cambiail carriage return del file
  dos2unix "$folder"/rss.tsv

  # crea copia del template del feed
  cp "$folder"/feedTemplate.xml "$folder"/feed.xml

  # inserisci gli attributi anagrafici nel feed
  xmlstarlet ed -L --subnode "//channel" --type elem -n title -v "$titolo" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n description -v "$descrizione" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n link -v "$selflink" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n "atom:link" -v "" -i "//*[name()='atom:link']" -t "attr" -n "rel" -v "self" -i "//*[name()='atom:link']" -t "attr" -n "href" -v "$selflink" -i "//*[name()='atom:link']" -t "attr" -n "type" -v "application/rss+xml" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n docs -v "$docs" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$type" -i "//channel/category[1]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-type" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$municipality" -i "//channel/category[2]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-municipality" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$province" -i "//channel/category[3]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-province" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$region" -i "//channel/category[4]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-region" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$latitude" -i "//channel/category[5]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-latitude" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$longitude" -i "//channel/category[6]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-longitude" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$country" -i "//channel/category[7]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-country" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$name" -i "//channel/category[8]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-name" "$folder"/feed.xml
  xmlstarlet ed -L --subnode "//channel" --type elem -n category -v "$uid" -i "//channel/category[9]" -t "attr" -n "domain" -v "http://albopop.it/specs#channel-category-uid" "$folder"/feed.xml

  # leggi in loop i dati del file TSV e usali per creare nuovi item nel file XML
  newcounter=0
  while IFS=$'\t' read -r href id des data allegati RSSdata guid; do
    newcounter=$(expr $newcounter + 1)
    xmlstarlet ed -L --subnode "//channel" --type elem -n item -v "" \
      --subnode "//item[$newcounter]" --type elem -n title -v "$des" \
      --subnode "//item[$newcounter]" --type elem -n description -v "$allegati" \
      --subnode "//item[$newcounter]" --type elem -n link -v "$guid" \
      --subnode "//item[$newcounter]" --type elem -n pubDate -v "$RSSdata" \
      --subnode "//item[$newcounter]" --type elem -n guid -v "$guid" \
      "$folder"/feed.xml
  done <"$folder"/rss.tsv

  host=$(hostname)

  # copia feed nella cartella web se non sei sul PC DESKTOP-7NVNDNF
  if [[ $host != "DESKTOP-7NVNDNF" ]]; then
    cp "$folder"/feed.xml "$web"/feed.xml
  fi

fi
