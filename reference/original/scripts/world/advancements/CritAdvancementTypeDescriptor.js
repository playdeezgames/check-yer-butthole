class CritAdvancementTypeDescriptor extends AdvancementTypeDescriptor{
    constructor(){
        super("Critical Check %", "Chance of getting a \"crit\" when checking yer butthole.", [1,2,4,8,16,32], [0,1,2,3,4,5,6]);
    }
    getEffectDescription(level){
        return `Crit chance ${this.getEffect(level)}%`;
    }
}
