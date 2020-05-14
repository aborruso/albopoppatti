#!/bin/bash

### requisiti ###
# miller https://github.com/johnkerl/miller
# dateutils https://github.com/hroptatyr/dateutils
### requisiti ###

set -x

folder="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$folder"/rawdata
mkdir -p "$folder"/processing

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

curl -ksL "http://www.comune.patti.me.it/index.php?option=com_albopretorio&id_Miky=_0" |
  scrape -be '//div[@id="albopretorio"]/ul//a' |
  xq -r '.html.body.a[]."@href"' >"$folder"/rawdata/pagine.txt

# cancella file html salvati
rm "$folder"/rawdata/*.html

# scarica file html nuovi sezione
x=1
while read p; do
  curl -kL "$urlbase""$p""&limit=50&limitstart=0" |  perl -pe 's/\r\n/ /g' >"$folder"/rawdata/"$x".html
  x=$(($x + 1))
done <"$folder"/rawdata/pagine.txt

# cancella file senza elementi
for i in "$folder"/rawdata/*.html; do
  if grep -q 'Nessun documento caricato' "$i"; then
    rm "$i"
  fi
done

# rimuovi CSV già creati
rm "$folder"/processing/*.csv

# estrai dai file HTML le info e inseriscile in dei file di esto
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

# unisci CSV sezioni
mlr --icsvlite --ocsv --ifs tab --implicit-csv-header unsparsify then label id,des,data,href then clean-whitespace "$folder"/processing/*_out.csv >"$folder"/pubblicazioni.csv
# fai JOIN con file allegati
mlr --csv join -j href -l href -r id -f "$folder"/pubblicazioni.csv then unsparsify "$folder"/rawdata/listaAllegati.csv >"$folder"/rss.csv
# rinomina colonna
mlr -I --csv rename source,allegati "$folder"/rss.csv
# rimuovi righe senza allegati
mlr -I --csv filter -x '$allegati==""' "$folder"/rss.csv

# convertire date in formato RSS
mlr -I --csv put '$RSSdata=system("dconv --from-locale it_IT -i \"%d %B %Y\" -f \"%a, %d %b %Y 02:00:00 +0200\" \"".$data."\"")' "$folder"/rss.csv
