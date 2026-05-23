.PHONY: all obmep-provas obmep-quebra-cabecas canguru

all: obmep-provas obmep-quebra-cabecas canguru

obmep-provas:
	ruby "OBMEP/Provas e Soluções/baixar_obmep_mirim.rb"

obmep-quebra-cabecas:
	ruby "OBMEP/Quebra Cabeças/baixar_quebra_cabecas.rb"

canguru:
	ruby "Canguru/baixar_canguru.rb"
