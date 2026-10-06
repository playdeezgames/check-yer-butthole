class AdvancementType{
    static descriptors={
        "Crit": new CritAdvancementTypeDescriptor(),
        "Thoroughness": new ThoroughnessAdvancementTypeDescriptor(),
        "IrritationRecovery": new IrritationRecoverySecondsAdvancementTypeDescriptor()
    };
    static initialize(character){
        for(let advancementType in AdvancementType.descriptors){
            character.setAdvancement(advancementType, 0);
        }
    }
}