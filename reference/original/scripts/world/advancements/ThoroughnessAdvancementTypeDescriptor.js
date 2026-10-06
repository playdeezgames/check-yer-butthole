class ThoroughnessAdvancementTypeDescriptor extends AdvancementTypeDescriptor{
    constructor(){
        super("Thoroughness", "You can't be too careful about this!", [5,10,15], [1,2,3,4])
    }
    getEffectDescription(level){
        return `Checks per click: ${this.getEffect(level)}`;
    }
}