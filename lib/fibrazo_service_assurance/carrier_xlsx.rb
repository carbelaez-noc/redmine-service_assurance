# frozen_string_literal: true

require 'zip'

module FibrazoServiceAssurance
  # XLSX mínimo sin gemas nuevas (usa rubyzip, ya presente en Redmine).
  # Una hoja, strings inline, estilos propios. Formato de entrega al carrier.
  class CarrierXlsx
    HEADERS = [
      'Ticket', 'Folio', 'Asunto', 'Cierre ticket', 'Fecha creado', 'Proveedor',
      'ID servicio', '# caso carrier', 'Tipo afectación', 'Inicio falla',
      'Fin falla', 'Inicio a objetar', 'Fin a objetar',
      'Minutos indisponibilidad', 'Clientes afectados', 'ANS aplica',
      'Conciliación aplica', 'Tiempos reconocidos (min)', 'Diferencia (min)',
      'Resultado', 'Crédito solicitado', 'Crédito reconocido', 'Motivo cierre ticket',
      'Motivo cierre SA', 'Estado SA', 'Evaluador'
    ].freeze

    def self.build(rows)
      new(rows).to_bytes
    end

    def initialize(rows)
      @rows = rows
    end

    def to_bytes
      buf = Zip::OutputStream.write_buffer do |zio|
        write_entry(zio, '[Content_Types].xml', content_types)
        write_entry(zio, '_rels/.rels', rels)
        write_entry(zio, 'xl/workbook.xml', workbook)
        write_entry(zio, 'xl/_rels/workbook.xml.rels', workbook_rels)
        write_entry(zio, 'xl/styles.xml', styles)
        write_entry(zio, 'xl/worksheets/sheet1.xml', sheet)
      end
      buf.string
    end

    private

    def write_entry(zio, name, content)
      zio.put_next_entry(name)
      zio.write(content)
    end

    def esc(value)
      value.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;').gsub('"', '&quot;')
    end

    def cell(ref, value, style = 0)
      "<c r=\"#{ref}\" t=\"inlineStr\" s=\"#{style}\"><is><t>#{esc(value)}</t></is></c>"
    end

    def col_name(idx)
      name = ''
      n = idx + 1
      while n.positive?
        n, r = (n - 1).divmod(26)
        name = (65 + r).chr + name
      end
      name
    end

    def sheet
      xml = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
             '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>']
      xml << row_xml(1, HEADERS, 1)
      @rows.each_with_index do |row, i|
        xml << row_xml(i + 2, row, 0)
      end
      xml << '</sheetData></worksheet>'
      xml.join
    end

    def row_xml(num, values, style)
      cells = values.each_with_index.map { |v, i| cell("#{col_name(i)}#{num}", v, style) }.join
      "<row r=\"#{num}\">#{cells}</row>"
    end

    def content_types
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
      XML
    end

    def rels
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
      XML
    end

    def workbook
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Conciliacion" sheetId="1" r:id="rId1"/></sheets></workbook>
      XML
    end

    def workbook_rels
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
      XML
    end

    def styles
      <<~XML
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts><font><sz val="11"/></font><font><b/><sz val="11"/></font></fonts><fills><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/><bgColor indexed="64"/></patternFill></fill></fills><borders><border/></borders><cellStyleXfs count="1"><xf/></cellStyleXfs><cellXfs count="2"><xf/><xf fontId="1" fillId="2" applyFont="1" applyFill="1"/></cellXfs></styleSheet>
      XML
    end
  end
end
