class IrritationRecoverySecondsAdvancementTypeDescriptor extends AdvancementTypeDescriptor{
    constructor(){
        super("Irritation Recovery", "Time in seconds before recovering irritation due to friction from checking.", [1,2,4,8,16,32], [60,55,50,45,40,35,30]);
    }
    getEffectDescription(level){
        return `Irritation Recovery Rate ${this.getEffect(level)}s`;
    }
}
