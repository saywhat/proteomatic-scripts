# Copyright (c) 2007-2008 Michael Specht
# 
# This file is part of Proteomatic.
# 
# Proteomatic is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# Proteomatic is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with Proteomatic.  If not, see <http://www.gnu.org/licenses/>.

require 'include/proteomatic'
require 'include/externaltools'
require 'include/fasta'
require 'include/formats'
require 'include/misc'
require 'yaml'
require 'fileutils'

class SimQuant < ProteomaticScript
	def cutMax(af_Value, ai_Max = 10000, ai_Places = 2)
		return af_Value > ai_Max.to_f ? ">#{ai_Max}" : sprintf("%1.#{ai_Places}f", af_Value)
	end
	
	def run()
		lk_Peptides = @param[:peptides].split(%r{[,;\s/]+})
		lk_Peptides.reject! { |x| x.strip.empty? }
		
		lk_Peptides.uniq!
		lk_Peptides.collect! { |x| x.upcase }
		if lk_Peptides.empty? && @input[:peptideFiles].empty?
			puts 'Error: no peptides have been specified.'
			exit 1
		end
		
		ls_TempPath = tempFilename('simquant')
		ls_YamlPath = File::join(ls_TempPath, 'out.yaml')
		ls_SvgPath = File::join(ls_TempPath, 'svg')
		FileUtils::mkpath(ls_TempPath)
		FileUtils::mkpath(ls_SvgPath)
		
		ls_Command = "\"#{ExternalTools::binaryPath('simquant.simquant')}\" --scanType #{@param[:scanType]} --isotopeCount #{@param[:isotopeCount]} --cropUpper #{@param[:cropUpper] / 100.0} --minSnr #{@param[:minSnr]} --maxOffCenter #{@param[:maxOffCenter] / 100.0} --maxTimeDifference #{@param[:maxTimeDifference]} --textOutput no --yamlOutput yes --yamlOutputTarget \"#{ls_YamlPath}\" --svgOutPath \"#{ls_SvgPath}\" --spectraFiles #{@input[:spectraFiles].collect {|x| '"' + x + '"'}.join(' ')} --peptides #{lk_Peptides.join(' ')} --peptideFiles #{@input[:peptideFiles].collect {|x| '"' + x + '"'}.join(' ')} --modelFiles #{@input[:modelFiles].collect {|x| '"' + x + '"'}.join(' ')}"
		runCommand(ls_Command, true)
		
		lk_Results = YAML::load_file(ls_YamlPath)
		
		if ((!lk_Results.include?('peptideResults')) || (lk_Results['peptideResults'].class != Hash) || (lk_Results['peptideResults'].size == 0))
			puts 'No peptides could be quantified.'
		else
			if @output[:xhtmlReport]
				File.open(@output[:xhtmlReport], 'w') do |lk_Out|
					lk_Out.puts "<?xml version='1.0' encoding='utf-8' ?>"
					lk_Out.puts "<!DOCTYPE html PUBLIC '-//W3C//DTD XHTML 1.1//EN' 'http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd'>"
					lk_Out.puts "<html xmlns='http://www.w3.org/1999/xhtml' xml:lang='de'>"
					lk_Out.puts '<head>'
					lk_Out.puts '<title>SimQuant Report</title>'
					lk_Out.puts '<style type=\'text/css\'>'
					lk_Out.puts 'body {font-family: Verdana; font-size: 10pt;}'
					lk_Out.puts 'h1 {font-size: 14pt;}'
					lk_Out.puts 'h2 {font-size: 12pt; border-top: 1px solid #888; border-bottom: 1px solid #888; padding-top: 0.2em; padding-bottom: 0.2em; background-color: #e8e8e8; }'
					lk_Out.puts 'h3 {font-size: 10pt; }'
					lk_Out.puts 'h4 {font-size: 10pt; font-weight: normal;}'
					lk_Out.puts 'ul {padding-left: 0;}'
					lk_Out.puts 'ol {padding-left: 0;}'
					lk_Out.puts 'li {margin-left: 2em;}'
					lk_Out.puts '.default { }'
					lk_Out.puts '.nonDefault { background-color: #ada;}'
					lk_Out.puts 'table {border-collapse: collapse;} '
					lk_Out.puts 'table tr {text-align: left; font-size: 10pt;}'
					lk_Out.puts 'table th, table td {vertical-align: top; border: 1px solid #888; padding: 0.2em;}'
					lk_Out.puts 'table tr.sub th, table tr.sub td {vertical-align: top; border: 1px dashed #888; padding: 0.2em;}'
					lk_Out.puts 'table th {font-weight: bold;}'
					lk_Out.puts '.gpf-confirm { background-color: #aed16f; }'
					lk_Out.puts '.toggle { padding: 0.2em; border: 1px solid #888; background-color: #f0f0f0; }'
					lk_Out.puts '.toggle:hover { cursor: pointer; border: 1px solid #000; background-color: #ddd; }'
					lk_Out.puts '.clickableCell { text-align: center; }'
					lk_Out.puts '.clickableCell:hover { cursor: pointer; }'
					lk_Out.puts '</style>'
					lk_Out.puts "<script type='text/javascript'>"
					lk_Out.puts "<![CDATA["
					lk_Out.puts
					
					lk_ProteinForPeptide = Hash.new
					lk_Results['proteinResults'].keys.each do |ls_Protein|
						lk_Results['proteinResults'][ls_Protein]['peptides'].each do |ls_Peptide|
							if (lk_ProteinForPeptide.include?(ls_Peptide))
								puts 'WARNING: Something went wrong. A peptide matches multiple proteins.'
							end
							lk_ProteinForPeptide[ls_Peptide] = ls_Protein
						end
					end
					
					lk_ScanIndex = Hash.new
					lk_PeptideAndFileIndex = Hash.new
					lk_PeptideIndex = Hash.new
					lk_ProteinIndex = Hash.new
					lk_Results['peptideResults'].keys.each do |ls_Peptide|
						lk_PeptideIndex[ls_Peptide] = "peptide-#{lk_PeptideIndex.size}"
						lk_Results['peptideResults'][ls_Peptide]['spots'].keys.each do |ls_Spot|
							ls_CompositeId = "#{ls_Peptide}-#{ls_Spot}"
							lk_PeptideAndFileIndex[ls_CompositeId] = "peptide-file-#{lk_PeptideAndFileIndex.size}"
							lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['scanResults'].each do |lk_Scan|
								ls_CompositeId = "#{ls_Peptide}-#{ls_Spot}-#{lk_Scan['id']}-#{lk_Scan['charge']}"
								lk_ScanIndex[ls_CompositeId] = "scan-#{lk_ScanIndex.size}"
							end
						end
					end
					
					unless (lk_Results['proteinResults'].empty?)
						lk_Results['proteinResults'].keys.each do |ls_Protein|
							lk_ProteinIndex[ls_Protein] = "protein-#{lk_ProteinIndex.size}"
						end
					end
					
					# write ratio and SNR for every single scan result
					lk_Out.puts "gk_RatioHash = new Object();"
					lk_Out.puts "gk_SnrHash = new Object();"
					lk_Results['peptideResults'].keys.each do |ls_Peptide|
						lk_Results['peptideResults'][ls_Peptide]['spots'].keys.each do |ls_Spot|
							lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['scanResults'].each do |lk_Scan|
								ls_Id = lk_ScanIndex["#{ls_Peptide}-#{ls_Spot}-#{lk_Scan['id']}-#{lk_Scan['charge']}"]
								lk_Out.puts "gk_RatioHash['#{ls_Id}'] = #{lk_Scan['ratio']};"
								lk_Out.puts "gk_SnrHash['#{ls_Id}'] = #{lk_Scan['snr']};"
							end
						end
					end
					lk_Out.puts
					
					# write which elements are affected when a scan is included/excluded
					lk_Out.puts "gk_AffectHash = new Object();"
					lk_Results['peptideResults'].keys.each do |ls_Peptide|
						lk_Results['peptideResults'][ls_Peptide]['spots'].keys.each do |ls_Spot|
							lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['scanResults'].each do |lk_Scan|
								ls_Id = lk_ScanIndex["#{ls_Peptide}-#{ls_Spot}-#{lk_Scan['id']}-#{lk_Scan['charge']}"]
								lk_Out.puts "gk_AffectHash['#{ls_Id}'] = new Array();"
								lk_Out.puts "gk_AffectHash['#{ls_Id}'].push('#{lk_PeptideAndFileIndex[ls_Peptide + '-' + ls_Spot]}');"
								lk_Out.puts "gk_AffectHash['#{ls_Id}'].push('#{lk_PeptideIndex[ls_Peptide]}');"
								if (lk_ProteinForPeptide.include?(ls_Peptide))
									lk_Out.puts "gk_AffectHash['#{ls_Id}'].push('#{lk_ProteinIndex[lk_ProteinForPeptide[ls_Peptide]]}');"
								end
							end
						end
					end
					lk_Out.puts
					
					# write from which scan results each result is calculated
					lk_Out.puts "gk_CalculationHash = new Object();"
					lk_Results['peptideResults'].keys.each do |ls_Peptide|
						lk_Results['peptideResults'][ls_Peptide]['spots'].keys.each do |ls_Spot|
							# write peptide-file calculations
							ls_Id = lk_PeptideAndFileIndex["#{ls_Peptide}-#{ls_Spot}"]
							lk_Out.puts "gk_CalculationHash['#{ls_Id}'] = new Array();"
							lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['scanResults'].each do |lk_Scan|
								lk_Out.puts "gk_CalculationHash['#{ls_Id}'].push('#{lk_ScanIndex["#{ls_Peptide}-#{ls_Spot}-#{lk_Scan['id']}-#{lk_Scan['charge']}"]}');"
							end
						end
						# write peptide calculations
						ls_Id = lk_PeptideIndex[ls_Peptide]
						lk_Out.puts "gk_CalculationHash['#{ls_Id}'] = new Array();"
						lk_Results['peptideResults'][ls_Peptide]['spots'].keys.each do |ls_Spot|
							lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['scanResults'].each do |lk_Scan|
								lk_Out.puts "gk_CalculationHash['#{ls_Id}'].push('#{lk_ScanIndex["#{ls_Peptide}-#{ls_Spot}-#{lk_Scan['id']}-#{lk_Scan['charge']}"]}');"
							end
						end
					end
					# write protein calculations
					lk_Results['proteinResults'].keys.each do |ls_Protein|
						ls_Id = lk_ProteinIndex[ls_Protein]
						lk_Out.puts "gk_CalculationHash['#{ls_Id}'] = new Array();"
						lk_Results['proteinResults'][ls_Protein]['peptides'].each do |ls_Peptide|
							lk_Results['peptideResults'][ls_Peptide]['spots'].keys.each do |ls_Spot|
								lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['scanResults'].each do |lk_Scan|
									lk_Out.puts "gk_CalculationHash['#{ls_Id}'].push('#{lk_ScanIndex["#{ls_Peptide}-#{ls_Spot}-#{lk_Scan['id']}-#{lk_Scan['charge']}"]}');"
								end
							end
						end
					end
					lk_Out.puts
					
					lk_Out.puts "function toggle(as_Name) {"
					lk_Out.puts "lk_Elements = document.getElementsByClassName(as_Name);"
					lk_Out.puts "for (var i = 0; i < lk_Elements.length; ++i)"
					lk_Out.puts "lk_Elements[i].style.display = lk_Elements[i].style.display == 'none' ? 'table-row' : 'none';"
					lk_Out.puts "}"
					lk_Out.puts "function show(as_Name) {"
					lk_Out.puts "lk_Elements = document.getElementsByClassName(as_Name);"
					lk_Out.puts "for (var i = 0; i < lk_Elements.length; ++i)"
					lk_Out.puts "lk_Elements[i].style.display = 'table-row';"
					lk_Out.puts "}"
					lk_Out.puts "function hide(as_Name) {"
					lk_Out.puts "lk_Elements = document.getElementsByClassName(as_Name);"
					lk_Out.puts "for (var i = 0; i < lk_Elements.length; ++i)"
					lk_Out.puts "lk_Elements[i].style.display = 'none';"
					lk_Out.puts "}"
					lk_Out.puts "var gs_Red = '#f08682';"
					lk_Out.puts "var gs_Green = '#b1d28f';"
					lk_Out.puts "function cutMax(ad_Value) {"
					lk_Out.puts "  if (ad_Value > 10000.0)"
					lk_Out.puts "    return '>10000';"
					lk_Out.puts "  return ad_Value.toFixed(2);"
					lk_Out.puts "}"
					lk_Out.puts "function includeExclude(as_Name) {"
					lk_Out.puts "lk_Element = document.getElementById('checker-' + as_Name);"
					lk_Out.puts "  if (lk_Element.firstChild.data == 'included') {"
					lk_Out.puts "    lk_Element.style.backgroundColor = gs_Red;"
					lk_Out.puts "    lk_Element.firstChild.data = 'excluded'"
					lk_Out.puts "  } else {"
					lk_Out.puts "    lk_Element.style.backgroundColor = gs_Green;"
					lk_Out.puts "    lk_Element.firstChild.data = 'included'"
					lk_Out.puts "  }"
					lk_Out.puts "  for (var i = 0; i < gk_AffectHash[as_Name].length; ++i) {"
					lk_Out.puts "    var ls_Target = gk_AffectHash[as_Name][i];"
					lk_Out.puts "    var lk_RatioList = new Array();"
					lk_Out.puts "    var lk_SnrList = new Array();"
					lk_Out.puts "    for (var k = 0; k < gk_CalculationHash[ls_Target].length; ++k) {"
					lk_Out.puts "      var ls_Scan = gk_CalculationHash[ls_Target][k];"
					lk_Out.puts "      if (document.getElementById('checker-' + ls_Scan).firstChild.data == 'included') {"
					lk_Out.puts "        lk_RatioList.push(gk_RatioHash[ls_Scan]);"
					lk_Out.puts "        lk_SnrList.push(gk_SnrHash[ls_Scan]);"
					lk_Out.puts "      }"
					lk_Out.puts "    }"
					lk_Out.puts "    // calculate mean and standard deviation"
					lk_Out.puts "    var ls_RatioMean = '-';"
					lk_Out.puts "    var ls_RatioStdDev = '-';"
					lk_Out.puts "    var ls_SnrMean = '-';"
					lk_Out.puts "    var ls_SnrStdDev = '-';"
					lk_Out.puts "    if (lk_RatioList.length > 0) {"
					lk_Out.puts "      ld_RatioMean = 0.0;"
					lk_Out.puts "      ld_RatioStdDev = 0.0;"
					lk_Out.puts "      for (var k = 0; k < lk_RatioList.length; ++k)"
					lk_Out.puts "        ld_RatioMean += lk_RatioList[k];"
					lk_Out.puts "      ld_RatioMean /= lk_RatioList.length;"
					lk_Out.puts "      for (var k = 0; k < lk_RatioList.length; ++k)"
					lk_Out.puts "        ld_RatioStdDev += Math.pow(lk_RatioList[k] - ld_RatioMean, 2.0);"
					lk_Out.puts "      ld_RatioStdDev /= lk_RatioList.length;"
					lk_Out.puts "      ld_RatioStdDev = Math.sqrt(ld_RatioStdDev);"
					lk_Out.puts "      ls_RatioMean = cutMax(ld_RatioMean)"
					lk_Out.puts "      ls_RatioStdDev = cutMax(ld_RatioStdDev);"
					lk_Out.puts "      ld_SnrMean = 0.0;"
					lk_Out.puts "      ld_SnrStdDev = 0.0;"
					lk_Out.puts "      for (var k = 0; k < lk_SnrList.length; ++k)"
					lk_Out.puts "        ld_SnrMean += lk_SnrList[k];"
					lk_Out.puts "      ld_SnrMean /= lk_SnrList.length;"
					lk_Out.puts "      for (var k = 0; k < lk_SnrList.length; ++k)"
					lk_Out.puts "        ld_SnrStdDev += Math.pow(lk_SnrList[k] - ld_SnrMean, 2.0);"
					lk_Out.puts "      ld_SnrStdDev /= lk_SnrList.length;"
					lk_Out.puts "      ld_SnrStdDev = Math.sqrt(ld_SnrStdDev);"
					lk_Out.puts "      ls_SnrMean = cutMax(ld_SnrMean)"
					lk_Out.puts "      ls_SnrStdDev = cutMax(ld_SnrStdDev);"
					lk_Out.puts "    }"
					lk_Out.puts "    lk_Elements = document.getElementsByClassName('ratio-m-' + ls_Target);"
					lk_Out.puts "    for (var k = 0; k < lk_Elements.length; ++k) lk_Elements[k].firstChild.data = ls_RatioMean;"
					lk_Out.puts "    lk_Elements = document.getElementsByClassName('ratio-s-' + ls_Target);"
					lk_Out.puts "    for (var k = 0; k < lk_Elements.length; ++k) lk_Elements[k].firstChild.data = ls_RatioStdDev;"
					lk_Out.puts "    lk_Elements = document.getElementsByClassName('snr-m-' + ls_Target);"
					lk_Out.puts "    for (var k = 0; k < lk_Elements.length; ++k) lk_Elements[k].firstChild.data = ls_SnrMean;"
					lk_Out.puts "    lk_Elements = document.getElementsByClassName('snr-s-' + ls_Target);"
					lk_Out.puts "    for (var k = 0; k < lk_Elements.length; ++k) lk_Elements[k].firstChild.data = ls_SnrStdDev;"
					lk_Out.puts "  }"
					lk_Out.puts "}"
					lk_Out.puts "var gk_Element;"
					lk_Out.puts "var gi_Phase; var gk_Timer;"
					lk_Out.puts "function fade() {"
					lk_Out.puts "gi_Phase++; s = gi_Phase; if (s > 16) s = 32 - s; "
					lk_Out.puts "r = Math.round((255 - (s * 64 / 16))).toString(16); if (r.length < 2) r = \"0\" + r;"
					lk_Out.puts "g = Math.round((255 - (s * 255 / 16))).toString(16); if (g.length < 2) g = \"0\" + g;"
					lk_Out.puts "b = Math.round((255 - (s * 255 / 16))).toString(16); if (b.length < 2) b = \"0\" + b;"
					lk_Out.puts "gk_Element.style.backgroundColor = \"#\" + r + g + b; //alert(r);"
					lk_Out.puts "if (gi_Phase >= 32) clearTimeout(gk_Timer); else gk_Timer = setTimeout(\"fade()\", 20);"
					lk_Out.puts "}"
					lk_Out.puts "function flashPeptide(as_Name) {"
					lk_Out.puts "lk_Element = document.getElementById(as_Name);"
					lk_Out.puts "gk_Element = lk_Element;"
					lk_Out.puts "gi_Phase = 0;"
					lk_Out.puts "gk_Timer = setTimeout(\"fade()\", 20);"
					lk_Out.puts "}"
					
					lk_Out.puts "]]>"
					lk_Out.puts "</script>"
					lk_Out.puts '</head>'
					lk_Out.puts '<body>'
					lk_Out.puts "<h1>SimQuant Report</h1>"
					lk_Out.puts '<p>'
					li_FoundPeptides = 0
					li_FoundProteins = 0
					li_FoundPeptides = lk_Results['peptideResults'].keys.size if lk_Results['peptideResults']
					li_FoundProteins = lk_Results['proteinResults'].keys.size if lk_Results['proteinResults']
					lk_Out.puts "Quantified #{li_FoundProteins} proteins with #{li_FoundPeptides} peptides in #{@input[:spectraFiles].size} spot file#{@input[:spectraFiles].size != 1 ? 's' : ''}."
					lk_Out.puts "Trying charge states #{@param[:minCharge]} to #{@param[:maxCharge]} and merging the upper #{@param[:cropUpper]}% (SNR) of all scans in which a peptide was found.<br />"
					lk_Out.puts "Quantitation has been attempted in #{@param[:scanType] == 'sim' ? 'SIM scans only' : 'all MS1 scans'}, considering #{@param[:isotopeCount]} isotope peaks for both the unlabeled and the labeled ions.<br />"
					lk_Out.puts '</p>'
					
					lk_Out.puts "<h2>Quantified proteins</h2>"
					
					if (lk_Results['ambiguousPeptides'])
						lk_Out.puts "<p><b>Attention:</b> The following peptides have been quantified but could not be assigned to a single proteins.</p>"
						lk_Out.puts "<table>"
						lk_Out.puts "<tr><th>Peptide</th><th>Proteins</th></tr>"
						lk_Results['ambiguousPeptides'].keys.each do |ls_Peptide|
							li_Count = 0
							li_Count = lk_Results['ambiguousPeptides'][ls_Peptide].size if lk_Results['ambiguousPeptides'][ls_Peptide]
							lk_Out.puts "<tr><td rowspan='#{li_Count == 0 ? 1 : li_Count}'>#{ls_Peptide}</td>"
							if (li_Count == 0)
								lk_Out.puts "<td><i>(unable to match to protein)</i></td>"
							else
								(0...li_Count).each do |li_Index|
									ls_Protein = lk_Results['ambiguousPeptides'][ls_Peptide][li_Index]
									lk_Out.puts "<tr>" unless li_Index == 0
									lk_Out.puts "<td>#{ls_Protein}</td>"
									lk_Out.puts "</tr>" unless li_Index == li_Count - 1
								end
							end
							lk_Out.puts "</tr>"
						end
						lk_Out.puts "</table>"
						lk_Out.puts "<p> </p>"
					end
					
					if (lk_Results['proteinResults'].size == 0)
						lk_Out.puts "<p><i>No proteins were quantified.</i></p>"
					else
						lk_Out.puts "<table>"
						lk_Out.puts "<tr><th rowspan='2'>Protein / Peptides</th><th colspan='2'>Ratio</th><th colspan='2'>SNR</th></tr>"
						lk_Out.puts "<tr><th>mean</th><th>std. dev.</th><th>mean</th><th>std. dev.</th></tr>"
						lk_ProteinKeys = lk_Results['proteinResults'].keys
						lk_ProteinKeys.sort! { |a, b| String::natcmp(a, b) }
						lk_ProteinKeys.each do |ls_Protein|
							lk_Out.puts "<tr><td style='border: none' colspan='6'></td></tr>"
							lk_Out.puts "<tr style='background-color: #eee;'>"
							lk_Out.puts "<td><b>#{ls_Protein}</b></td>"
							lk_Out.puts "<td class='ratio-m-#{lk_ProteinIndex[ls_Protein]}' style='text-align: right;'>#{cutMax(lk_Results['proteinResults'][ls_Protein]['mergedResults']['ratioMean'])}</td>"
							lk_Out.puts "<td class='ratio-s-#{lk_ProteinIndex[ls_Protein]}' style='text-align: right;'>#{cutMax(lk_Results['proteinResults'][ls_Protein]['mergedResults']['ratioStdDev'])}</td>"
							lk_Out.puts "<td class='snr-m-#{lk_ProteinIndex[ls_Protein]}' style='text-align: right;'>#{cutMax(lk_Results['proteinResults'][ls_Protein]['mergedResults']['snrMean'])}</td>"
							lk_Out.puts "<td class='snr-s-#{lk_ProteinIndex[ls_Protein]}' style='text-align: right;'>#{cutMax(lk_Results['proteinResults'][ls_Protein]['mergedResults']['snrStdDev'])}</td>"
							lk_Out.puts "</tr>"
							lk_Results['proteinResults'][ls_Protein]['peptides'].each do |ls_Peptide|
								lk_Out.puts "<tr>"
								lk_Out.puts "<td><a href='#peptide-#{ls_Peptide}'>#{ls_Peptide}</a></td>"
								lk_Out.puts "<td class='ratio-m-#{lk_PeptideIndex[ls_Peptide]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['mergedResults']['ratioMean'])}</td>"
								lk_Out.puts "<td class='ratio-s-#{lk_PeptideIndex[ls_Peptide]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['mergedResults']['ratioStdDev'])}</td>"
								lk_Out.puts "<td class='snr-m-#{lk_PeptideIndex[ls_Peptide]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['mergedResults']['snrMean'])}</td>"
								lk_Out.puts "<td class='snr-s-#{lk_PeptideIndex[ls_Peptide]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['mergedResults']['snrStdDev'])}</td>"
								lk_Out.puts "</tr>"
							end
						end
						lk_Out.puts "</table>"
					end
					
					lk_Out.puts "<h2>Quantified peptides</h2>"
					
=begin					
					lk_Out.puts "<p>"
					lk_Out.puts "<span class='toggle' onclick=\"show('scans-all');\">show all scans</span> "
					lk_Out.puts "<span class='toggle' onclick=\"hide('scans-all');\">hide all scans</span> <br />"
					lk_Out.puts "</p>"
=end					
					
					lk_Out.puts "<table style='min-width: 820px;'>"
					lk_Out.puts "<tr><th rowspan='2'>Peptide / Spot / Scan</th><th colspan='2'>Ratio</th><th colspan='2'>SNR</th><th rowspan='2'>manual exclusion</th></tr>"
					lk_Out.puts "<tr><th>mean</th><th>std. dev.</th><th>mean</th><th>std. dev.</th></tr>"
					lk_PeptideKeys = lk_Results['peptideResults'].keys
					lk_PeptideKeys.sort! { |a, b| String::natcmp(a, b) }
					lk_PeptideKeys.each do |ls_Peptide|
						lk_Out.puts "<tr><td style='border: none' colspan='6'></td></tr>"
						lk_Out.puts "<tr style='background-color: #ddd;' id='peptide-#{ls_Peptide}'><td><b>#{ls_Peptide}</b></td>"
						lk_Out.puts "<td class='ratio-m-#{lk_PeptideIndex[ls_Peptide]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['mergedResults']['ratioMean'])}</td>"
						lk_Out.puts "<td class='ratio-s-#{lk_PeptideIndex[ls_Peptide]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['mergedResults']['ratioStdDev'])}</td>"
						lk_Out.puts "<td class='snr-m-#{lk_PeptideIndex[ls_Peptide]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['mergedResults']['snrMean'])}</td>"
						lk_Out.puts "<td class='snr-s-#{lk_PeptideIndex[ls_Peptide]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['mergedResults']['snrStdDev'])}</td>"
						lk_Out.puts "<td></td>"
						lk_Out.puts "</tr>"
						
						lk_SpotKeys = lk_Results['peptideResults'][ls_Peptide]['spots'].keys
						lk_SpotKeys.sort! { |a, b| String::natcmp(a, b) }
						lk_SpotKeys.each do |ls_Spot|
							lk_Out.puts "<tr><td style='border: none' colspan='6'></td></tr>"
							lk_Out.puts "<tr style='background-color: #eee;' id='peptide-#{ls_Peptide}-spot-#{ls_Spot}'><td>#{ls_Spot}</td>"
							lk_Out.puts "<td class='ratio-m-#{lk_PeptideAndFileIndex[ls_Peptide + '-' + ls_Spot]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['mergedResults']['ratioMean'])}</td>"
							lk_Out.puts "<td class='ratio-s-#{lk_PeptideAndFileIndex[ls_Peptide + '-' + ls_Spot]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['mergedResults']['ratioStdDev'])}</td>"
							lk_Out.puts "<td class='snr-m-#{lk_PeptideAndFileIndex[ls_Peptide + '-' + ls_Spot]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['mergedResults']['snrMean'])}</td>"
							lk_Out.puts "<td class='snr-s-#{lk_PeptideAndFileIndex[ls_Peptide + '-' + ls_Spot]}' style='text-align: right;'>#{cutMax(lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['mergedResults']['snrStdDev'])}</td>"
							lk_Out.puts "<td></td>"
							lk_Out.puts "</tr>"
							
							lk_Scans = lk_Results['peptideResults'][ls_Peptide]['spots'][ls_Spot]['scanResults']
							lk_Scans.sort! { |a, b| a['retentionTime'] <=> b['retentionTime'] }
							lk_Scans.each do |lk_Scan|
								ls_CompositeId = lk_ScanIndex["#{ls_Peptide}-#{ls_Spot}-#{lk_Scan['id']}-#{lk_Scan['charge']}"]
								lk_Out.puts "<tr><td style='border: none' colspan='6'></td></tr>"
								lk_Out.puts "<tr><td>scan ##{lk_Scan['id']} (charge #{lk_Scan['charge']}+)</td>"
								lk_Out.puts "<td style='text-align: right;'>#{cutMax(lk_Scan['ratio'])}</td>"
								lk_Out.puts "<td style='border-left: none;'></td>"
								lk_Out.puts "<td style='text-align: right;'>#{cutMax(lk_Scan['snr'])}</td>"
								lk_Out.puts "<td style='border-left: none;'></td>"
								lk_Out.puts "<td id='checker-#{ls_CompositeId}' style='background-color: #b1d28f;' class='clickableCell' onclick='includeExclude(\"#{ls_CompositeId}\")'>included</td>"
								#lk_Out.puts "<td style='background-color: #f08682;' class='clickableCell'>excluded</td>"
								
								lk_Out.puts "</tr>"
								
								ls_Svg = File::read(File::join(ls_SvgPath, lk_Scan['svg'] + '.svg'))
								ls_Svg.sub!(/<\?xml.+\?>/, '')
								ls_Svg.sub!(/<svg width=\".+\" height=\".+\"/, "<svg ")
								lk_Out.puts "<tr><td colspan='6'>"
								lk_Out.puts "<div>#{ls_Spot} ##{lk_Scan['id']} @ #{sprintf("%1.2f", lk_Scan['retentionTime'].to_f)} minutes: charge: #{lk_Scan['charge']}+ / #{lk_Scan['filterLine']}</div>"
								lk_Out.puts ls_Svg
								lk_Out.puts "</td></tr>"
							end
						end
					end
					lk_Out.puts "</table>"
					lk_Out.puts '</body>'
					lk_Out.puts '</html>'
				end
			end
		end
	end
end

lk_Object = SimQuant.new
